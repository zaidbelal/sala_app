const assert = require("node:assert/strict");

const projectId = process.env.GCLOUD_PROJECT;
if (!projectId) throw new Error("GCLOUD_PROJECT must be set by the Firebase emulator");

const firestoreUrl =
  `http://127.0.0.1:8080/v1/projects/${projectId}/databases/(default)/documents`;
const authUrl =
  "http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-api-key";
const functionsUrl = `http://127.0.0.1:5001/${projectId}/us-central1`;

async function assertStatus(response, expected, description) {
  if (response.status !== expected) {
    throw new Error(
      `${description}: expected ${expected}, got ${response.status}: ${await response.text()}`,
    );
  }
}

async function firestoreRequest(path, token, method = "GET", body) {
  return fetch(`${firestoreUrl}/${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
      ...(body ? { "Content-Type": "application/json" } : {}),
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
}

async function callFunction(name, data, token) {
  const response = await fetch(`${functionsUrl}/${name}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify({ data }),
  });
  const result = await response.json();
  await assertStatus(response, 200, name);
  return result.result;
}

async function expectFunctionFailure(name, data, token) {
  const response = await fetch(`${functionsUrl}/${name}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify({ data }),
  });
  assert.notEqual(response.status, 200, `${name} should reject conflicting input`);
}

function numericField(document, name) {
  const value = document.fields[name];
  if (!value) return 0;
  const rounded = Math.round(
    Number(value.integerValue ?? value.doubleValue ?? value.stringValue) * 100,
  ) / 100;
  return Object.is(rounded, -0) ? 0 : rounded;
}

async function readDocument(path, token) {
  const response = await firestoreRequest(path, token);
  await assertStatus(response, 200, `Read ${path}`);
  return response.json();
}

async function main() {
  const signupResponse = await fetch(authUrl, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      email: `ledger-test-${Date.now()}@example.test`,
      password: "ledger-test-password",
      returnSecureToken: true,
    }),
  });
  await assertStatus(signupResponse, 200, "Create ledger test merchant");
  const account = await signupResponse.json();

  const profileResponse = await firestoreRequest(
    `profiles/${account.localId}`,
    "owner",
    "PATCH",
    {
      fields: {
        role: { stringValue: "merchant" },
        is_active: { booleanValue: true },
        is_banned: { booleanValue: false },
      },
    },
  );
  await assertStatus(profileResponse, 200, "Seed active merchant profile");

  const customerId = "concurrency-ledger-customer";
  const customerResponse = await firestoreRequest(
    `merchant_customers/${customerId}`,
    "owner",
    "PATCH",
    {
      fields: {
        merchant_id: { stringValue: account.localId },
        name: { stringValue: "Concurrency test customer" },
        current_balance: { doubleValue: "0" },
        credit_limit: { doubleValue: "100000" },
        ledger_version: { integerValue: "0" },
        is_deleted: { booleanValue: false },
      },
    },
  );
  await assertStatus(customerResponse, 200, "Seed ledger test customer");

  const debtId = "concurrent-debt-entry";
  const debtPayload = {
    transactionId: debtId,
    customerId,
    type: "debt",
    amount: 12.34,
  };
  const debtResults = await Promise.all(
    Array.from({ length: 12 }, () =>
      callFunction("recordLedgerTransaction", debtPayload, account.idToken),
    ),
  );
  assert.equal(debtResults.filter((result) => result.success).length, 12);
  assert.equal(
    debtResults.filter((result) => result.alreadyRecorded === false).length,
    1,
    "Concurrent retries must apply a ledger entry exactly once",
  );

  await expectFunctionFailure(
    "recordLedgerTransaction",
    { ...debtPayload, amount: 99 },
    account.idToken,
  );
  await expectFunctionFailure(
    "recordLedgerTransaction",
    { ...debtPayload, notes: "different transaction" },
    account.idToken,
  );
  await expectFunctionFailure(
    "recordLedgerTransaction",
    {
      ...debtPayload,
      items: [
        {
          product_id: "different-product",
          name: "Different product",
          quantity: 1,
          unit_label: "piece",
          unit_price: 12.34,
          subtotal: 12.34,
          carton_capacity: 1,
        },
      ],
    },
    account.idToken,
  );
  await expectFunctionFailure(
    "recordLedgerTransaction",
    {
      transactionId: "invalid-ledger-item",
      customerId,
      type: "debt",
      amount: 12.34,
      items: [
        {
          product_id: "invalid-quantity",
          name: "Invalid quantity",
          quantity: -1,
          unit_label: "piece",
          unit_price: 12.34,
          subtotal: 12.34,
          carton_capacity: 1,
        },
      ],
    },
    account.idToken,
  );

  const paymentId = "concurrent-payment-entry";
  const paymentResults = await Promise.all(
    Array.from({ length: 8 }, () =>
      callFunction(
        "recordLedgerTransaction",
        {
          transactionId: paymentId,
          customerId,
          type: "payment",
          amount: 3.21,
        },
        account.idToken,
      ),
    ),
  );
  assert.equal(
    paymentResults.filter((result) => result.alreadyRecorded === false).length,
    1,
    "Concurrent payment retries must apply exactly once",
  );

  let customer = await readDocument(`merchant_customers/${customerId}`, account.idToken);
  assert.equal(numericField(customer, "current_balance"), 9.13);
  let summary = await readDocument(
    `merchant_ledger_summaries/${account.localId}`,
    account.idToken,
  );
  assert.equal(numericField(summary, "total_market_debt"), 9.13);
  assert.equal(numericField(summary, "debtors_count"), 1);

  const voidResults = await Promise.all(
    Array.from({ length: 12 }, () =>
      callFunction(
        "voidLedgerTransaction",
        { customerId, entryId: debtId },
        account.idToken,
      ),
    ),
  );
  assert.equal(
    voidResults.filter((result) => result.alreadyVoided !== true).length,
    1,
    "Concurrent void retries must reverse an entry exactly once",
  );

  await callFunction(
    "voidLedgerTransaction",
    { customerId, entryId: paymentId },
    account.idToken,
  );
  customer = await readDocument(`merchant_customers/${customerId}`, account.idToken);
  assert.equal(numericField(customer, "current_balance"), 0);
  summary = await readDocument(
    `merchant_ledger_summaries/${account.localId}`,
    account.idToken,
  );
  assert.equal(numericField(summary, "total_market_debt"), 0);
  assert.equal(numericField(summary, "debtors_count"), 0);

  const reconciliation = await callFunction(
    "reconcileLedgerBalance",
    { customerId },
    account.idToken,
  );
  assert.equal(reconciliation.reconciled, true);

  const debtBeforeDeleteId = "debt-before-customer-delete";
  await callFunction(
    "recordLedgerTransaction",
    {
      transactionId: debtBeforeDeleteId,
      customerId,
      type: "debt",
      amount: 5,
    },
    account.idToken,
  );
  await callFunction(
    "deleteLedgerCustomer",
    { customerId },
    account.idToken,
  );
  summary = await readDocument(
    `merchant_ledger_summaries/${account.localId}`,
    account.idToken,
  );
  assert.equal(numericField(summary, "total_market_debt"), 0);
  assert.equal(numericField(summary, "debtors_count"), 0);

  await callFunction(
    "voidLedgerTransaction",
    { customerId, entryId: debtBeforeDeleteId },
    account.idToken,
  );
  customer = await readDocument(
    `merchant_customers/${customerId}`,
    account.idToken,
  );
  assert.equal(numericField(customer, "current_balance"), 0);
  summary = await readDocument(
    `merchant_ledger_summaries/${account.localId}`,
    account.idToken,
  );
  assert.equal(numericField(summary, "total_market_debt"), 0);
  assert.equal(numericField(summary, "debtors_count"), 0);

  const deleteCustomerResponse = await firestoreRequest(
    `merchant_customers/${customerId}?updateMask.fieldPaths=is_deleted`,
    "owner",
    "PATCH",
    { fields: { is_deleted: { booleanValue: true } } },
  );
  await assertStatus(deleteCustomerResponse, 200, "Mark ledger test customer deleted");
  await expectFunctionFailure(
    "reconcileLedgerBalance",
    { customerId },
    account.idToken,
  );

  console.log("Concurrent ledger idempotency and atomicity tests passed.");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

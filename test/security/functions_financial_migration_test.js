const assert = require("node:assert/strict");

const projectId = process.env.GCLOUD_PROJECT;
if (!projectId) throw new Error("GCLOUD_PROJECT must be set by the Firebase emulator");

const firestoreUrl =
  `http://127.0.0.1:8080/v1/projects/${projectId}/databases/(default)/documents`;
const authUrl =
  "http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-api-key";
const functionsUrl = `http://127.0.0.1:5001/${projectId}/us-central1`;

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
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify({ data }),
  });
  const result = await response.json();
  assert.equal(response.status, 200, `${name}: ${JSON.stringify(result)}`);
  return result.result;
}

async function assertFunctionDenied(name, data, token) {
  const response = await fetch(`${functionsUrl}/${name}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify({ data }),
  });
  assert.equal(response.status, 403, `${name} should reject this role: ${await response.text()}`);
}

async function main() {
  const accountResponse = await fetch(authUrl, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      email: `migration-test-${Date.now()}@example.test`,
      password: "migration-test-password",
      returnSecureToken: true,
    }),
  });
  assert.equal(accountResponse.status, 200, "Create admin test account");
  const account = await accountResponse.json();
  const adminProfile = await firestoreRequest(`profiles/${account.localId}`, "owner", "PATCH", {
    fields: {
      role: { stringValue: "admin" },
      is_active: { booleanValue: true },
      is_banned: { booleanValue: false },
    },
  });
  assert.equal(adminProfile.status, 200, "Seed active admin profile");
  const nonMerchantCalls = [
    ["addLedgerCustomer", { name: "Unauthorized customer" }],
    ["deleteLedgerCustomer", { customerId: "unauthorized-ledger-customer" }],
    [
      "recordLedgerTransaction",
      {
        transactionId: "unauthorized-ledger-operation",
        customerId: "unauthorized-ledger-customer",
        type: "debt",
        amount: 1,
      },
    ],
    [
      "voidLedgerTransaction",
      {
        customerId: "unauthorized-ledger-customer",
        entryId: "unauthorized-ledger-entry",
      },
    ],
    ["reconcileLedgerBalance", { customerId: "unauthorized-ledger-customer" }],
    ["logCustomerReminder", { customerId: "unauthorized-ledger-customer" }],
    [
      "placeOrder",
      {
        orderId: "unauthorized-order",
        items: [{ product_id: "unneeded" }],
      },
    ],
  ];
  for (const [name, data] of nonMerchantCalls) {
    await assertFunctionDenied(name, data, account.idToken);
  }

  await firestoreRequest("products/legacy-product", "owner", "PATCH", {
    fields: {
      id: { stringValue: "legacy-product" },
      name: { stringValue: "Legacy product" },
      price: { integerValue: "150" },
      cost_price: { integerValue: "100" },
      units: {
        arrayValue: {
          values: [{
            mapValue: {
              fields: {
                label: { stringValue: "unit" },
                price: { integerValue: "20" },
                cost_price: { integerValue: "12" },
                qty: { integerValue: "1" },
              },
            },
          }],
        },
      },
    },
  });
  await firestoreRequest("orders/legacy-order", "owner", "PATCH", {
    fields: {
      merchant_id: { stringValue: account.localId },
      status: { stringValue: "delivered" },
      total_profit: { integerValue: "50" },
      profit_recorded: { booleanValue: true },
    },
  });
  await firestoreRequest("order_items/legacy-item", "owner", "PATCH", {
    fields: {
      order_id: { stringValue: "legacy-order" },
      merchant_id: { stringValue: account.localId },
      cost_price: { integerValue: "100" },
      unit_cost: { integerValue: "12" },
    },
  });

  let migrationResult;
  for (let attempt = 0; attempt < 20; attempt++) {
    migrationResult = await callFunction(
      "migrateFinancialFields",
      {},
      account.idToken,
    );
    if (migrationResult.done === true) break;
  }
  assert.equal(migrationResult?.done, true, "Financial migration should finish");

  const safeProductResponse = await firestoreRequest("products/legacy-product", "owner");
  const safeProduct = await safeProductResponse.json();
  assert.equal(safeProduct.fields.public_catalog_ready.booleanValue, true);
  assert.equal("cost_price" in safeProduct.fields, false);
  const publicUnit =
    safeProduct.fields.units.arrayValue.values[0].mapValue.fields;
  assert.equal("cost_price" in publicUnit, false);

  const privateProductResponse =
    await firestoreRequest("product_financials/legacy-product", "owner");
  const privateProduct = await privateProductResponse.json();
  assert.equal(privateProduct.fields.cost_price.integerValue, "100");
  assert.equal(
    privateProduct.fields.units.arrayValue.values[0].mapValue.fields.cost_price.integerValue,
    "12",
  );

  const safeOrderResponse = await firestoreRequest("orders/legacy-order", "owner");
  const safeOrder = await safeOrderResponse.json();
  assert.equal(safeOrder.fields.financial_safe.booleanValue, true);
  assert.equal("total_profit" in safeOrder.fields, false);
  const privateOrderResponse =
    await firestoreRequest("order_financials/legacy-order", "owner");
  assert.equal((await privateOrderResponse.json()).fields.total_profit.integerValue, "50");

  const safeItemResponse = await firestoreRequest("order_items/legacy-item", "owner");
  const safeItem = await safeItemResponse.json();
  assert.equal("unit_cost" in safeItem.fields, false);
  const privateItemResponse =
    await firestoreRequest("order_item_financials/legacy-item", "owner");
  assert.equal((await privateItemResponse.json()).fields.unit_cost.integerValue, "12");

  const checkExisting = await callFunction("checkPhoneNumber", {
    phone: "+967777777001",
  });
  const checkMissing = await callFunction("checkPhoneNumber", {
    phone: "+967777777002",
  });
  assert.deepEqual(checkExisting, checkMissing, "Phone check must not reveal account existence");

  const verifyExisting = await callFunction("verifyOtp", {
    phone: "+967777777001",
    code: "123456",
    purpose: "login",
  });
  const verifyMissing = await callFunction("verifyOtp", {
    phone: "+967777777002",
    code: "123456",
    purpose: "login",
  });
  assert.deepEqual(verifyExisting, verifyMissing, "OTP errors must not reveal account existence");

  console.log("Financial migration and account privacy tests passed.");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

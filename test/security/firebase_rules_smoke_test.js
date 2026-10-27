const assert = require("node:assert/strict");

const projectId = process.env.GCLOUD_PROJECT;
if (!projectId) throw new Error("GCLOUD_PROJECT must be set by the Firebase emulator");

const firestoreUrl =
  `http://127.0.0.1:8080/v1/projects/${projectId}/databases/(default)/documents`;
const authUrl =
  "http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-api-key";
const storageUrl = `http://127.0.0.1:9199/v0/b/${projectId}.appspot.com/o`;

async function createAuthUser() {
  const response = await fetch(authUrl, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      email: `rules-test-${Date.now()}@example.test`,
      password: "rules-test-password",
      returnSecureToken: true,
    }),
  });
  await assertStatus(response, 200, "Auth emulator sign-up");
  const data = await response.json();
  return { token: data.idToken, userId: data.localId };
}

async function assertStatus(response, expected, description) {
  if (response.status !== expected) {
    throw new Error(`${description}: expected ${expected}, got ${response.status}: ${await response.text()}`);
  }
}

async function firestoreRequest(path, token, method, body) {
  const url = path.startsWith(":")
    ? `${firestoreUrl}${path}`
    : `${firestoreUrl}/${path}`;
  return fetch(url, {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
      ...(body ? { "Content-Type": "application/json" } : {}),
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
}

async function uploadStorageObject(path, token) {
  const url = `${storageUrl}?uploadType=media&name=${encodeURIComponent(path)}`;
  return fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "image/png",
    },
    body: Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
  });
}

async function assertDenied(path, body, token) {
  const response = await firestoreRequest(path, token, "POST", body);
  assert.equal(response.status, 403, `${path} should be denied: ${await response.text()}`);
}

async function main() {
  const { token, userId } = await createAuthUser();
  const userProfileSeed = await firestoreRequest(`profiles/${userId}`, "owner", "PATCH", {
    fields: {
      role: { stringValue: "merchant" },
      is_active: { booleanValue: true },
      is_banned: { booleanValue: false },
    },
  });
  await assertStatus(userProfileSeed, 200, "Seed merchant profile");

  const adminToken = "owner";
  const ownLedgerCustomerSeed = await firestoreRequest(
    "merchant_customers/own-ledger-customer",
    adminToken,
    "PATCH",
    { fields: { merchant_id: { stringValue: userId }, name: { stringValue: "Own customer" } } },
  );
  await assertStatus(ownLedgerCustomerSeed, 200, "Seed own ledger customer");
  const otherLedgerCustomerSeed = await firestoreRequest(
    "merchant_customers/other-ledger-customer",
    adminToken,
    "PATCH",
    { fields: { merchant_id: { stringValue: "another-merchant" } } },
  );
  await assertStatus(otherLedgerCustomerSeed, 200, "Seed another merchant's ledger customer");
  const ownLedgerEntrySeed = await firestoreRequest(
    "merchant_ledger_entries/own-ledger-entry",
    adminToken,
    "PATCH",
    {
      fields: {
        merchant_id: { stringValue: userId },
        customer_id: { stringValue: "own-ledger-customer" },
        type: { stringValue: "debt" },
        amount: { integerValue: "20" },
      },
    },
  );
  await assertStatus(ownLedgerEntrySeed, 200, "Seed own ledger entry");
  const otherLedgerEntrySeed = await firestoreRequest(
    "merchant_ledger_entries/other-ledger-entry",
    adminToken,
    "PATCH",
    {
      fields: {
        merchant_id: { stringValue: "another-merchant" },
        customer_id: { stringValue: "other-ledger-customer" },
        type: { stringValue: "debt" },
        amount: { integerValue: "30" },
      },
    },
  );
  await assertStatus(otherLedgerEntrySeed, 200, "Seed another merchant's ledger entry");
  const ownLedgerSummarySeed = await firestoreRequest(
    `merchant_ledger_summaries/${userId}`,
    adminToken,
    "PATCH",
    {
      fields: {
        merchant_id: { stringValue: userId },
        total_market_debt: { integerValue: "20" },
      },
    },
  );
  await assertStatus(ownLedgerSummarySeed, 200, "Seed own ledger summary");
  const ownRetailPricingSeed = await firestoreRequest(
    `profiles/${userId}/retail_pricing/product-1`,
    adminToken,
    "PATCH",
    {
      fields: {
        price: { integerValue: "25" },
        updated_at: { timestampValue: new Date().toISOString() },
      },
    },
  );
  await assertStatus(ownRetailPricingSeed, 200, "Seed own retail pricing");

  const otherOrderPath = "orders/other-merchant-order";
  const otherOrderBody = {
    fields: {
      merchant_id: { stringValue: "another-merchant" },
      status: { stringValue: "pending" },
      total: { integerValue: "100" },
    },
  };
  const seedResponse = await firestoreRequest(otherOrderPath, adminToken, "PATCH", otherOrderBody);
  await assertStatus(seedResponse, 200, "Seed other merchant order");
  const unsafeOrderSeed = await firestoreRequest("orders/legacy-order", adminToken, "PATCH", {
    fields: {
      merchant_id: { stringValue: userId },
      status: { stringValue: "delivered" },
      total_profit: { integerValue: "50" },
    },
  });
  await assertStatus(unsafeOrderSeed, 200, "Seed legacy order with private profit");
  const legacyItemSeed = await firestoreRequest("order_items/legacy-item", adminToken, "PATCH", {
    fields: {
      order_id: { stringValue: "legacy-order" },
      merchant_id: { stringValue: userId },
      unit_cost: { integerValue: "20" },
    },
  });
  await assertStatus(legacyItemSeed, 200, "Seed legacy order item with private cost");

  const ownOrderPath = `orders/${userId}-own-order`;
  const ownOrderBody = {
    fields: {
      merchant_id: { stringValue: userId },
      status: { stringValue: "pending" },
      total: { integerValue: "100" },
      financial_safe: { booleanValue: true },
    },
  };
  const ownSeedResponse = await firestoreRequest(ownOrderPath, adminToken, "PATCH", ownOrderBody);
  await assertStatus(ownSeedResponse, 200, "Seed own order");

  const ownItemPath = "order_items/own-item";
  const ownItemSeed = await firestoreRequest(ownItemPath, adminToken, "PATCH", {
    fields: {
      order_id: { stringValue: `${userId}-own-order` },
      merchant_id: { stringValue: userId },
    },
  });
  await assertStatus(ownItemSeed, 200, "Seed own order item");

  const otherItemSeed = await firestoreRequest("order_items/other-item", adminToken, "PATCH", {
    fields: {
      order_id: { stringValue: "other-merchant-order" },
      merchant_id: { stringValue: "another-merchant" },
    },
  });
  await assertStatus(otherItemSeed, 200, "Seed other order item");

  const ownNotificationPath = `user_notifications/${userId}-note`;
  const ownNotificationSeed = await firestoreRequest(ownNotificationPath, adminToken, "PATCH", {
    fields: {
      user_id: { stringValue: userId },
      title: { stringValue: "Test" },
      is_read: { booleanValue: false },
    },
  });
  await assertStatus(ownNotificationSeed, 200, "Seed own notification");

  const ownOrderResponse = await firestoreRequest(ownOrderPath, token, "GET");
  assert.equal(ownOrderResponse.status, 200, "merchants should read their own orders");
  assert.equal(
    (await firestoreRequest("orders/legacy-order", token, "GET")).status,
    403,
    "merchants must not read legacy orders until financial fields are migrated",
  );
  assert.equal(
    (await firestoreRequest("order_items/legacy-item", token, "GET")).status,
    403,
    "merchants must not read legacy order items before financial-field migration",
  );

  const otherOrderResponse = await firestoreRequest(otherOrderPath, token, "GET");
  assert.equal(otherOrderResponse.status, 403, "merchants must not read another merchant's orders");
  assert.equal(
    (await firestoreRequest("merchant_customers/own-ledger-customer", token, "GET")).status,
    200,
    "merchants should read their own ledger customers",
  );
  assert.equal(
    (await firestoreRequest("merchant_customers/other-ledger-customer", token, "GET")).status,
    403,
    "merchants must not read another merchant's ledger customers",
  );
  assert.equal(
    (await firestoreRequest("merchant_ledger_entries/own-ledger-entry", token, "GET")).status,
    200,
    "merchants should read their own ledger entries",
  );
  assert.equal(
    (await firestoreRequest("merchant_ledger_entries/other-ledger-entry", token, "GET")).status,
    403,
    "merchants must not read another merchant's ledger entries",
  );
  assert.equal(
    (await firestoreRequest(`merchant_ledger_summaries/${userId}`, token, "GET")).status,
    200,
    "merchants should read their own ledger summary",
  );
  assert.equal(
    (await firestoreRequest("profiles/another-merchant/retail_pricing/product-1", token, "GET")).status,
    403,
    "merchants must not read another merchant's retail pricing",
  );
  assert.equal(
    (await firestoreRequest(`profiles/${userId}/retail_pricing/product-1`, token, "GET")).status,
    200,
    "merchants should read their own retail pricing",
  );
  const ownRetailPricingUpdate = await firestoreRequest(
    `profiles/${userId}/retail_pricing/product-1`,
    token,
    "PATCH",
    {
      fields: {
        price: { integerValue: "30" },
        updated_at: { timestampValue: new Date().toISOString() },
      },
    },
  );
  assert.equal(ownRetailPricingUpdate.status, 200, "merchants may update their own retail pricing");
  assert.equal(
    (
      await firestoreRequest(
        "profiles/another-merchant/retail_pricing/product-1",
        token,
        "PATCH",
        {
          fields: {
            price: { integerValue: "30" },
            updated_at: { timestampValue: new Date().toISOString() },
          },
        },
      )
    ).status,
    403,
    "merchants must not update another merchant's retail pricing",
  );
  await assertDenied(
    "merchant_ledger_entries?documentId=forged-ledger-entry",
    { fields: { merchant_id: { stringValue: userId }, amount: { integerValue: "999" } } },
    token,
  );
  await assertDenied(
    "merchant_customers?documentId=forged-ledger-customer",
    { fields: { merchant_id: { stringValue: userId } } },
    token,
  );

  assert.equal(
    (await firestoreRequest(ownItemPath, token, "GET")).status,
    200,
    "merchants should read their own order items",
  );
  assert.equal(
    (await firestoreRequest("order_items/other-item", token, "GET")).status,
    403,
    "merchants must not read another merchant's order items",
  );

  const safeProductSeed = await firestoreRequest("products/safe-product", "owner", "PATCH", {
    fields: {
      name: { stringValue: "Safe product" },
      public_catalog_ready: { booleanValue: true },
    },
  });
  await assertStatus(safeProductSeed, 200, "Seed sanitized catalog product");
  assert.equal(
    (await firestoreRequest("products/safe-product", token, "GET")).status,
    200,
    "merchants may read sanitized catalog products",
  );
  const unsafeProductSeed = await firestoreRequest("products/unsafe-product", "owner", "PATCH", {
    fields: {
      name: { stringValue: "Unsafe product" },
      cost_price: { integerValue: "25" },
    },
  });
  await assertStatus(unsafeProductSeed, 200, "Seed legacy product with private cost");
  assert.equal(
    (await firestoreRequest("products/unsafe-product", token, "GET")).status,
    403,
    "merchants must not read catalog products before financial-field migration",
  );
  const privateCostSeed = await firestoreRequest("product_financials/safe-product", "owner", "PATCH", {
    fields: { cost_price: { integerValue: "25" } },
  });
  await assertStatus(privateCostSeed, 200, "Seed private product cost");
  assert.equal(
    (await firestoreRequest("product_financials/safe-product", token, "GET")).status,
    403,
    "merchants must not read product financial records",
  );
  const privateItemCostSeed = await firestoreRequest(
    "order_item_financials/own-item",
    "owner",
    "PATCH",
    { fields: { unit_cost: { integerValue: "10" } } },
  );
  await assertStatus(privateItemCostSeed, 200, "Seed private order item cost");
  assert.equal(
    (await firestoreRequest("order_item_financials/own-item", token, "GET")).status,
    403,
    "merchants must not read order item financial records",
  );

  const ownItemsQuery = await firestoreRequest(":runQuery", token, "POST", {
    structuredQuery: {
      from: [{ collectionId: "order_items" }],
      where: {
        fieldFilter: {
          field: { fieldPath: "order_id" },
          op: "EQUAL",
          value: { stringValue: `${userId}-own-order` },
        },
      },
    },
  });
  await assertStatus(ownItemsQuery, 200, "Query own order items");

  const markReadResponse = await firestoreRequest(
    `${ownNotificationPath}?updateMask.fieldPaths=is_read`,
    token,
    "PATCH",
    { fields: { is_read: { booleanValue: true } } },
  );
  assert.equal(markReadResponse.status, 200, "users may mark their own notifications as read");

  const editNotificationResponse = await firestoreRequest(
    `${ownNotificationPath}?updateMask.fieldPaths=title`,
    token,
    "PATCH",
    { fields: { title: { stringValue: "Forged" } } },
  );
  assert.equal(editNotificationResponse.status, 403, "users must not edit notification content");

  const { token: unprofiledToken, userId: unprofiledId } = await createAuthUser();
  await assertDenied(
    `profiles?documentId=${unprofiledId}`,
    { fields: { role: { stringValue: "admin" } } },
    unprofiledToken,
  );
  await assertDenied(
    "orders?documentId=forged-order",
    { fields: { merchant_id: { stringValue: userId } } },
    token,
  );
  await assertDenied(
    "order_items?documentId=forged-item",
    { fields: { order_id: { stringValue: otherOrderPath.split("/")[1] } } },
    token,
  );
  await assertDenied(
    "user_notifications?documentId=forged-notification",
    { fields: { user_id: { stringValue: "another-user" } } },
    token,
  );
  await assertDenied(
    "products?documentId=forged-product",
    { fields: { name: { stringValue: "Forged" } } },
    token,
  );
  await assertDenied(
    "order_returns?documentId=forged-return",
    { fields: { merchant_id: { stringValue: userId } } },
    token,
  );

  const merchantImageUpload = await uploadStorageObject(`images/${userId}.png`, token);
  assert.equal(merchantImageUpload.status, 403, "merchants must not upload catalog images");

  const signatureUpload = await uploadStorageObject(`signatures/${userId}.png`, token);
  assert.equal(signatureUpload.status, 403, "clients must not upload signatures directly");

  const { token: adminTokenForStorage, userId: adminId } = await createAuthUser();
  const adminProfileSeed = await firestoreRequest(`profiles/${adminId}`, "owner", "PATCH", {
    fields: {
      role: { stringValue: "admin" },
      is_active: { booleanValue: true },
      is_banned: { booleanValue: false },
    },
  });
  await assertStatus(adminProfileSeed, 200, "Seed administrator profile");
  const orderFinancialSeed = await firestoreRequest(
    "order_financials/return-write-test",
    "owner",
    "PATCH",
    { fields: { total_profit: { integerValue: "10" } } },
  );
  await assertStatus(orderFinancialSeed, 200, "Seed private order financial record");
  assert.equal(
    (await firestoreRequest("order_financials/return-write-test", token, "GET")).status,
    403,
    "merchants must not read order financial records",
  );
  assert.equal(
    (await firestoreRequest("order_financials/return-write-test", adminTokenForStorage, "GET")).status,
    200,
    "administrators may read order financial records",
  );
  assert.equal(
    (await firestoreRequest("product_financials/safe-product", adminTokenForStorage, "GET")).status,
    200,
    "administrators may read product financial records",
  );

  const returnSeed = await firestoreRequest("order_returns/return-write-test", "owner", "PATCH", {
    fields: {
      merchant_id: { stringValue: userId },
      order_id: { stringValue: `${userId}-own-order` },
      status: { stringValue: "pending" },
    },
  });
  await assertStatus(returnSeed, 200, "Seed return for write authorization test");
  const adminReturnUpdate = await firestoreRequest(
    "order_returns/return-write-test?updateMask.fieldPaths=status",
    adminTokenForStorage,
    "PATCH",
    { fields: { status: { stringValue: "accepted" } } },
  );
  assert.equal(adminReturnUpdate.status, 403, "return status changes must use the trusted server flow");

  await assertDenied(
    "products?documentId=admin-forged-product",
    { fields: { name: { stringValue: "Forged" } } },
    adminTokenForStorage,
  );

  const adminImageUpload = await uploadStorageObject(`images/${adminId}.png`, adminTokenForStorage);
  await assertStatus(adminImageUpload, 200, "Administrators may upload catalog images");

  console.log("Firebase security rule smoke tests passed.");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

import { describe, expect, it, beforeAll } from "vitest";
import { readFileSync } from "fs";
import { join } from "path";

describe("Rent-to-Own Contract Validation", () => {
  let contractContent: string;

  beforeAll(() => {
    // Read the contract file
    const contractPath = join(process.cwd(), "contracts", "Rent-to-Own-Contract.clar");
    contractContent = readFileSync(contractPath, "utf-8");
  });

  it("should have contract file present", () => {
    expect(contractContent).toBeDefined();
    expect(contractContent.length).toBeGreaterThan(0);
  });

  it("should contain core rent-to-own functions", () => {
    const coreFunctions = [
      "initialize-contract",
      "make-payment",
      "check-payment-status",
      "cancel-contract"
    ];

    coreFunctions.forEach(func => {
      expect(contractContent).toContain(`define-public (${func}`);
    });
  });

  it("should contain maintenance system functions", () => {
    const maintenanceFunctions = [
      "submit-maintenance-request",
      "update-request-status",
      "assign-maintenance-worker"
    ];

    maintenanceFunctions.forEach(func => {
      expect(contractContent).toContain(`define-public (${func}`);
    });
  });

  it("should contain maintenance read-only functions", () => {
    const readOnlyFunctions = [
      "get-maintenance-request",
      "get-maintenance-history",
      "get-request-counter",
      "get-property-maintenance-summary"
    ];

    readOnlyFunctions.forEach(func => {
      expect(contractContent).toContain(`define-read-only (${func}`);
    });
  });

  it("should have proper error constants", () => {
    const errorConstants = [
      "ERR-UNAUTHORIZED",
      "ERR-INVALID-AMOUNT",
      "ERR-INVALID-REQUEST",
      "ERR-REQUEST-NOT-FOUND",
      "ERR-UNAUTHORIZED-UPDATE",
      "ERR-INVALID-PRIORITY",
      "ERR-INVALID-STATUS-TRANSITION"
    ];

    errorConstants.forEach(error => {
      expect(contractContent).toContain(`define-constant ${error}`);
    });
  });

  it("should have maintenance data maps", () => {
    const dataMaps = [
      "maintenance-requests",
      "maintenance-history"
    ];

    dataMaps.forEach(map => {
      expect(contractContent).toContain(`define-map ${map}`);
    });
  });

  it("should have core rent-to-own data maps", () => {
    const coreMaps = [
      "properties",
      "escrow-balances",
      "payment-history"
    ];

    coreMaps.forEach(map => {
      expect(contractContent).toContain(`define-map ${map}`);
    });
  });

  it("should use proper Clarity v3 data types", () => {
    // Check for proper string types
    expect(contractContent).toContain("string-utf8");
    expect(contractContent).toContain("string-ascii");
    expect(contractContent).toContain("optional");
  });

  it("should have maintenance priority validation", () => {
    const priorities = ["LOW", "MEDIUM", "HIGH", "CRITICAL"];
    
    priorities.forEach(priority => {
      expect(contractContent).toContain(`"${priority}"`);
    });
  });

  it("should have maintenance status workflow", () => {
    const statuses = ["PENDING", "APPROVED", "IN_PROGRESS", "COMPLETED", "REJECTED"];
    
    statuses.forEach(status => {
      expect(contractContent).toContain(`"${status}"`);
    });
  });

  it("should have proper authorization checks", () => {
    // Check for authorization patterns
    expect(contractContent).toContain("asserts!");
    expect(contractContent).toContain("is-eq tx-sender");
    expect(contractContent).toContain("contract-owner");
  });

  it("should have comprehensive error handling", () => {
    // Check for error handling patterns
    expect(contractContent).toContain("unwrap!");
    expect(contractContent).toContain("err ");
    expect(contractContent).toContain("try!");
  });
});
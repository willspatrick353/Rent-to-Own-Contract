import { describe, expect, it, beforeEach } from "vitest";

const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer")!;
const wallet1 = accounts.get("wallet_1")!;
const wallet2 = accounts.get("wallet_2")!;
const wallet3 = accounts.get("wallet_3")!;

describe("Rent-to-Own Contract Tests", () => {
  beforeEach(() => {
    simnet.blockHeight = 1;
  });

  describe("Contract Initialization", () => {
    it("should initialize contract successfully with valid parameters", () => {
      const { result } = simnet.callPublicFn(
        "Rent-to-Own-Contract",
        "initialize-contract",
        [
          Cl.uint(1), // property-id
          Cl.principal(wallet1), // tenant
          Cl.uint(1000000), // total-amount (1 STX)
          Cl.uint(100000), // monthly-amount (0.1 STX)
        ],
        deployer
      );
      expect(result).toBeOk(Cl.bool(true));
    });

    it("should fail to initialize with zero total amount", () => {
      const { result } = simnet.callPublicFn(
        "Rent-to-Own-Contract",
        "initialize-contract",
        [
          Cl.uint(1),
          Cl.principal(wallet1),
          Cl.uint(0), // zero amount
          Cl.uint(100000),
        ],
        deployer
      );
      expect(result).toBeErr(Cl.uint(2)); // ERR-INVALID-AMOUNT
    });

    it("should fail when non-owner tries to initialize", () => {
      const { result } = simnet.callPublicFn(
        "Rent-to-Own-Contract",
        "initialize-contract",
        [
          Cl.uint(1),
          Cl.principal(wallet2),
          Cl.uint(1000000),
          Cl.uint(100000),
        ],
        wallet1 // not the deployer
      );
      expect(result).toBeErr(Cl.uint(1)); // ERR-UNAUTHORIZED
    });
  });

  describe("Payment System", () => {
    beforeEach(() => {
      // Initialize contract for payment tests
      simnet.callPublicFn(
        "Rent-to-Own-Contract",
        "initialize-contract",
        [
          Cl.uint(1),
          Cl.principal(wallet1),
          Cl.uint(1000000),
          Cl.uint(100000),
        ],
        deployer
      );
    });

    it("should process payment successfully from tenant", () => {
      const { result } = simnet.callPublicFn(
        "Rent-to-Own-Contract",
        "make-payment",
        [Cl.uint(1)],
        wallet1 // tenant
      );
      expect(result).toBeOk(Cl.bool(true));
    });

    it("should check payment status correctly", () => {
      // Make a payment first
      simnet.callPublicFn(
        "Rent-to-Own-Contract",
        "make-payment",
        [Cl.uint(1)],
        wallet1
      );

      const { result } = simnet.callPublicFn(
        "Rent-to-Own-Contract",
        "check-payment-status",
        [Cl.uint(1)],
        deployer
      );
      
      expect(result).toBeOk(
        Cl.tuple({
          "payments-made": Cl.uint(1),
          "total-payments": Cl.uint(10),
          "last-payment": Cl.uint(simnet.blockHeight),
          "status": Cl.stringAscii("ACTIVE"),
        })
      );
    });
  });

  describe("Maintenance Request System", () => {
    beforeEach(() => {
      // Initialize contract for maintenance tests
      simnet.callPublicFn(
        "Rent-to-Own-Contract",
        "initialize-contract",
        [
          Cl.uint(1),
          Cl.principal(wallet1),
          Cl.uint(1000000),
          Cl.uint(100000),
        ],
        deployer
      );
    });

    it("should submit maintenance request successfully", () => {
      const { result } = simnet.callPublicFn(
        "Rent-to-Own-Contract",
        "submit-maintenance-request",
        [
          Cl.principal(deployer), // property-owner
          Cl.stringUtf8("Plumbing"), // category
          Cl.stringUtf8("Leaky faucet in kitchen needs repair"), // description
          Cl.stringAscii("MEDIUM"), // priority
          Cl.uint(50000), // estimated-cost
        ],
        wallet1 // tenant submitting request
      );
      expect(result).toBeOk(Cl.uint(1)); // request-id
    });

    it("should fail maintenance request with invalid priority", () => {
      const { result } = simnet.callPublicFn(
        "Rent-to-Own-Contract",
        "submit-maintenance-request",
        [
          Cl.principal(deployer),
          Cl.stringUtf8("Electrical"),
          Cl.stringUtf8("Fix outlet"),
          Cl.stringAscii("URGENT"), // invalid priority
          Cl.uint(30000),
        ],
        wallet1
      );
      expect(result).toBeErr(Cl.uint(93)); // ERR-INVALID-PRIORITY
    });

    it("should update request status successfully", () => {
      // Submit request first
      simnet.callPublicFn(
        "Rent-to-Own-Contract",
        "submit-maintenance-request",
        [
          Cl.principal(deployer),
          Cl.stringUtf8("HVAC"),
          Cl.stringUtf8("Air conditioning not working"),
          Cl.stringAscii("HIGH"),
          Cl.uint(200000),
        ],
        wallet1
      );

      const { result } = simnet.callPublicFn(
        "Rent-to-Own-Contract",
        "update-request-status",
        [
          Cl.uint(1), // request-id
          Cl.stringAscii("APPROVED"), // new-status
          Cl.some(Cl.stringUtf8("Request approved by property owner")), // notes
          Cl.none(), // assigned-to
        ],
        deployer // property owner
      );
      expect(result).toBeOk(Cl.bool(true));
    });

    it("should assign maintenance worker successfully", () => {
      // Submit and approve request first
      simnet.callPublicFn(
        "Rent-to-Own-Contract",
        "submit-maintenance-request",
        [
          Cl.principal(deployer),
          Cl.stringUtf8("Electrical"),
          Cl.stringUtf8("Replace light fixtures"),
          Cl.stringAscii("LOW"),
          Cl.uint(75000),
        ],
        wallet1
      );

      simnet.callPublicFn(
        "Rent-to-Own-Contract",
        "update-request-status",
        [
          Cl.uint(1),
          Cl.stringAscii("APPROVED"),
          Cl.none(),
          Cl.none(),
        ],
        deployer
      );

      const { result } = simnet.callPublicFn(
        "Rent-to-Own-Contract",
        "assign-maintenance-worker",
        [
          Cl.uint(1), // request-id
          Cl.principal(wallet2), // worker
          Cl.some(Cl.stringUtf8("Assigned to certified electrician")), // notes
        ],
        deployer
      );
      expect(result).toBeOk(Cl.bool(true));
    });

    it("should get maintenance request details correctly", () => {
      // Submit request first
      simnet.callPublicFn(
        "Rent-to-Own-Contract",
        "submit-maintenance-request",
        [
          Cl.principal(deployer),
          Cl.stringUtf8("Painting"),
          Cl.stringUtf8("Repaint living room walls"),
          Cl.stringAscii("LOW"),
          Cl.uint(40000),
        ],
        wallet1
      );

      const { result } = simnet.callReadOnlyFn(
        "Rent-to-Own-Contract",
        "get-maintenance-request",
        [Cl.uint(1)],
        wallet1
      );

      expect(result).toBeSome(
        Cl.tuple({
          "property-owner": Cl.principal(deployer),
          "requester": Cl.principal(wallet1),
          "request-height": Cl.uint(simnet.blockHeight),
          "category": Cl.stringUtf8("Painting"),
          "description": Cl.stringUtf8("Repaint living room walls"),
          "priority": Cl.stringAscii("LOW"),
          "status": Cl.stringAscii("PENDING"),
          "estimated-cost": Cl.uint(40000),
          "completion-height": Cl.none(),
          "assigned-to": Cl.none(),
        })
      );
    });
  });

  describe("Contract Management", () => {
    beforeEach(() => {
      simnet.callPublicFn(
        "Rent-to-Own-Contract",
        "initialize-contract",
        [
          Cl.uint(1),
          Cl.principal(wallet1),
          Cl.uint(1000000),
          Cl.uint(100000),
        ],
        deployer
      );
    });

    it("should cancel contract successfully by owner", () => {
      const { result } = simnet.callPublicFn(
        "Rent-to-Own-Contract",
        "cancel-contract",
        [Cl.uint(1)],
        deployer
      );
      expect(result).toBeOk(Cl.bool(true));
    });

    it("should fail contract cancellation by unauthorized user", () => {
      const { result } = simnet.callPublicFn(
        "Rent-to-Own-Contract",
        "cancel-contract",
        [Cl.uint(1)],
        wallet2 // not owner or tenant
      );
      expect(result).toBeErr(Cl.uint(41)); // ERR-CANCELLATION-UNAUTHORIZED
    });
  });

  describe("Read-Only Functions", () => {
    beforeEach(() => {
      simnet.callPublicFn(
        "Rent-to-Own-Contract",
        "initialize-contract",
        [
          Cl.uint(1),
          Cl.principal(wallet1),
          Cl.uint(1000000),
          Cl.uint(100000),
        ],
        deployer
      );
    });

    it("should get property details correctly", () => {
      const { result } = simnet.callReadOnlyFn(
        "Rent-to-Own-Contract",
        "get-property-details",
        [Cl.principal(deployer)],
        wallet1
      );

      expect(result).toBeSome(
        Cl.tuple({
          "owner": Cl.principal(deployer),
          "tenant": Cl.principal(wallet1),
          "property-id": Cl.uint(1),
          "start-height": Cl.uint(simnet.blockHeight),
          "total-amount": Cl.uint(1000000),
          "monthly-amount": Cl.uint(100000),
          "payments-completed": Cl.uint(0),
          "status": Cl.stringAscii("ACTIVE"),
          "next-payment-due": Cl.uint(simnet.blockHeight + 30),
          "late-fees-owed": Cl.uint(0),
        })
      );
    });

    it("should get request counter correctly", () => {
      const { result } = simnet.callReadOnlyFn(
        "Rent-to-Own-Contract",
        "get-request-counter",
        [],
        wallet1
      );
      expect(result).toBeUint(0);
    });

    it("should get property maintenance summary", () => {
      const { result } = simnet.callReadOnlyFn(
        "Rent-to-Own-Contract",
        "get-property-maintenance-summary",
        [Cl.principal(deployer)],
        wallet1
      );

      expect(result).toBeOk(
        Cl.tuple({
          "total-requests": Cl.uint(0),
          "property-status": Cl.stringAscii("ACTIVE"),
          "last-payment-height": Cl.uint(0),
        })
      );
    });
  });

  describe("Integration Tests", () => {
    it("should handle complete workflow: contract init -> maintenance request -> payment", () => {
      // Initialize contract
      simnet.callPublicFn(
        "Rent-to-Own-Contract",
        "initialize-contract",
        [
          Cl.uint(1),
          Cl.principal(wallet1),
          Cl.uint(1000000),
          Cl.uint(100000),
        ],
        deployer
      );

      // Submit maintenance request
      const requestResult = simnet.callPublicFn(
        "Rent-to-Own-Contract",
        "submit-maintenance-request",
        [
          Cl.principal(deployer),
          Cl.stringUtf8("General Maintenance"),
          Cl.stringUtf8("Monthly property inspection and minor repairs"),
          Cl.stringAscii("MEDIUM"),
          Cl.uint(25000),
        ],
        wallet1
      );
      expect(requestResult.result).toBeOk(Cl.uint(1));

      // Make payment
      const paymentResult = simnet.callPublicFn(
        "Rent-to-Own-Contract",
        "make-payment",
        [Cl.uint(1)],
        wallet1
      );
      expect(paymentResult.result).toBeOk(Cl.bool(true));

      // Approve maintenance request
      const approvalResult = simnet.callPublicFn(
        "Rent-to-Own-Contract",
        "update-request-status",
        [
          Cl.uint(1),
          Cl.stringAscii("APPROVED"),
          Cl.some(Cl.stringUtf8("Approved after payment received")),
          Cl.none(),
        ],
        deployer
      );
      expect(approvalResult.result).toBeOk(Cl.bool(true));

      // Verify state consistency
      const propertyDetails = simnet.callReadOnlyFn(
        "Rent-to-Own-Contract",
        "get-property-details",
        [Cl.principal(deployer)],
        wallet1
      );
      
      const maintenanceRequest = simnet.callReadOnlyFn(
        "Rent-to-Own-Contract",
        "get-maintenance-request",
        [Cl.uint(1)],
        wallet1
      );

      expect(propertyDetails.result).toBeSome(
        Cl.tuple({
          "owner": Cl.principal(deployer),
          "tenant": Cl.principal(wallet1),
          "property-id": Cl.uint(1),
          "start-height": Cl.uint(1),
          "total-amount": Cl.uint(1000000),
          "monthly-amount": Cl.uint(100000),
          "payments-completed": Cl.uint(1),
          "status": Cl.stringAscii("ACTIVE"),
          "next-payment-due": Cl.uint(32), // current height + 30 + 1
          "late-fees-owed": Cl.uint(0),
        })
      );

      expect(maintenanceRequest.result).toBeSome(
        Cl.tuple({
          "property-owner": Cl.principal(deployer),
          "requester": Cl.principal(wallet1),
          "request-height": Cl.uint(2),
          "category": Cl.stringUtf8("General Maintenance"),
          "description": Cl.stringUtf8("Monthly property inspection and minor repairs"),
          "priority": Cl.stringAscii("MEDIUM"),
          "status": Cl.stringAscii("APPROVED"),
          "estimated-cost": Cl.uint(25000),
          "completion-height": Cl.none(),
          "assigned-to": Cl.none(),
        })
      );
    });
  });
});
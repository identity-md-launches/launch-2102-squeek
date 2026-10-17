// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Squeek} from "../src/Squeek.sol";

/// @dev Exercises a closed set of holders and maintains independent accounting for each action.
contract SqueekHandler is Test {
    Squeek private immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(Squeek token_) {
        token = token_;
        actors[0] = makeAddr("invariant holder 0");
        actors[1] = makeAddr("invariant holder 1");
        actors[2] = makeAddr("invariant holder 2");
        actors[3] = makeAddr("invariant holder 3");
        expectedBalance[actors[0]] = 1_000_000_000 * 10 ** 18;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 amount = bound(amountSeed, 0, expectedBalance[from]);

        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 allowanceSeed, bool unlimited) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        // Finite approvals may exceed the supply; only uint256.max is unlimited.
        uint256 amount = unlimited ? type(uint256).max : bound(allowanceSeed, 0, type(uint256).max - 1);

        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address spender = actors[spenderSeed % actors.length];
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 approved = expectedAllowance[from][spender];
        uint256 balance = expectedBalance[from];
        uint256 amount = bound(amountSeed, 0, approved < balance ? approved : balance);

        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
        if (approved != type(uint256).max) {
            expectedAllowance[from][spender] = approved - amount;
        }
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function revoke(uint256 ownerSeed, uint256 spenderSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, 0));
        expectedAllowance[owner][spender] = 0;
    }

    function transferEntireBalance(uint256 fromSeed, uint256 toSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 amount = expectedBalance[from];
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function rejectTransferOverBalance(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[from];
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max);
        _reject(
            from,
            abi.encodeCall(token.transfer, (to, amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount)
        );
    }

    function rejectTransferFrom(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address spender = actors[spenderSeed % actors.length];
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 approved = expectedAllowance[from][spender];
        uint256 balance = expectedBalance[from];
        // Always exceed at least one limit, using the existing approval rather than
        // granting a new one. This checks rejection after arbitrary prior actions.
        uint256 limit = approved < balance ? approved : balance;
        uint256 amount = bound(amountSeed, limit + 1, type(uint256).max);
        bytes memory reason = amount > approved
            ? abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, amount)
            : abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount);
        _reject(spender, abi.encodeCall(token.transferFrom, (from, to, amount)), reason);
    }

    function rejectTransferToZero(uint256 fromSeed, uint256 amountSeed) external {
        address from = actors[fromSeed % actors.length];
        uint256 amount = bound(amountSeed, 0, expectedBalance[from]);
        _reject(
            from,
            abi.encodeCall(token.transfer, (address(0), amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
    }

    function rejectTransferFromToZero(uint256 spenderSeed, uint256 fromSeed, uint256 amountSeed) external {
        address spender = actors[spenderSeed % actors.length];
        address from = actors[fromSeed % actors.length];
        uint256 approved = expectedAllowance[from][spender];
        uint256 balance = expectedBalance[from];
        uint256 amount = bound(amountSeed, 0, approved < balance ? approved : balance);
        // An otherwise authorized spend must roll its allowance debit back when
        // the recipient is invalid, including zero spends and unlimited approvals.
        _reject(
            spender,
            abi.encodeCall(token.transferFrom, (from, address(0), amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
    }

    function rejectApprovalToZero(uint256 ownerSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        _reject(
            owner,
            abi.encodeCall(token.approve, (address(0), amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0))
        );
    }

    function _reject(address caller, bytes memory data, bytes memory expectedError) private {
        vm.prank(caller);
        (bool success, bytes memory reason) = address(token).call(data);
        assertFalse(success, "invalid operation succeeded");
        assertEq(reason, expectedError, "unexpected rejection reason");
        // No ghost update: both invariants must still match the pre-call state.
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract SqueekInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    Squeek private token;
    SqueekHandler private handler;

    function setUp() public {
        token = new Squeek();
        handler = new SqueekHandler(token);
        assertTrue(token.transfer(handler.actors(0), SUPPLY));

        // Fund every actor and seed both finite and unlimited approvals so a
        // random sequence starts with meaningful delegated transfers available.
        for (uint256 i = 1; i < 4; ++i) {
            handler.transfer(0, i, SUPPLY / 4);
        }
        for (uint256 i; i < 4; ++i) {
            handler.approve(i, (i + 1) % 4, SUPPLY / 8, false);
            handler.approve(i, (i + 2) % 4, 0, true);
        }

        bytes4[] memory selectors = new bytes4[](10);
        selectors[0] = SqueekHandler.transfer.selector;
        selectors[1] = SqueekHandler.approve.selector;
        selectors[2] = SqueekHandler.transferFrom.selector;
        selectors[3] = SqueekHandler.revoke.selector;
        selectors[4] = SqueekHandler.transferEntireBalance.selector;
        selectors[5] = SqueekHandler.rejectTransferOverBalance.selector;
        selectors[6] = SqueekHandler.rejectTransferFrom.selector;
        selectors[7] = SqueekHandler.rejectTransferToZero.selector;
        selectors[8] = SqueekHandler.rejectTransferFromToZero.selector;
        selectors[9] = SqueekHandler.rejectApprovalToZero.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_SupplyRemainsFixedAndFullyAccounted() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            sum += token.balanceOf(handler.actors(i));
        }
        assertEq(sum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(this)), 0);
    }

    function invariant_BalancesAndAllowancesMatchAccounting() public view {
        for (uint256 i; i < 4; ++i) {
            address owner = handler.actors(i);
            assertEq(token.balanceOf(owner), handler.expectedBalance(owner));
            assertEq(token.allowance(owner, address(0)), 0);
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
        }
    }

    function invariant_MetadataRemainsUnchanged() public view {
        assertEq(token.name(), "Squeek");
        assertEq(token.symbol(), "SQK");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
    }

    function afterInvariant() public {
        // After any random history, each holder can still transfer its full
        // balance. A pause or hidden lock would make this collection fail.
        for (uint256 i = 1; i < 4; ++i) {
            handler.transferEntireBalance(i, 0);
            assertEq(token.balanceOf(handler.actors(i)), 0);
        }
        assertEq(token.balanceOf(handler.actors(0)), SUPPLY);
        invariant_SupplyRemainsFixedAndFullyAccounted();
        invariant_BalancesAndAllowancesMatchAccounting();
        invariant_MetadataRemainsUnchanged();
    }
}

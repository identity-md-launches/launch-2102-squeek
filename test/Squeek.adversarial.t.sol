// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Squeek} from "src/Squeek.sol";

/// @dev Receiving ordinary ERC-20 tokens must not require a callback.
contract SqueekRejectingRecipient {
    fallback() external {
        revert("recipient cannot be called");
    }
}

/// @dev Complements the deployment and ERC-20 tests with boundary and sequence properties.
/// forge-config: default.fuzz.runs = 1000
contract SqueekAdversarialTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    Squeek private token;
    address private alice;
    address private bob;
    address private spender;
    address private otherSpender;

    function setUp() public {
        token = new Squeek();
        alice = makeAddr("boundary holder alice");
        bob = makeAddr("boundary holder bob");
        spender = makeAddr("boundary spender");
        otherSpender = makeAddr("boundary other spender");
    }

    function test_OneSmallestUnitMovesExactlyAndCanBeReturned() public {
        assertTrue(token.transfer(alice, 1));
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        vm.prank(alice);
        assertTrue(token.transfer(address(this), 1));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaxMinusOneAllowanceIsFiniteAndDecreasesOnEverySpend() public {
        uint256 approved = type(uint256).max - 1;
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), approved - 1);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, SUPPLY - 1));
        assertEq(token.allowance(address(this), spender), approved - SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(bob), SUPPLY - 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumTransferFailsWithoutArithmeticPanicAndHolderCanStillSpend() public {
        _expectBalanceError(address(this), SUPPLY, type(uint256).max);
        token.transfer(alice, type(uint256).max);
        _expectBalanceError(address(this), SUPPLY, type(uint256).max);
        token.transfer(address(this), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_UnlimitedApprovalCannotSpendMoreThanBalance() public {
        assertTrue(token.approve(spender, type(uint256).max));
        _expectBalanceError(address(this), SUPPLY, type(uint256).max);
        vm.prank(spender);
        token.transferFrom(address(this), alice, type(uint256).max);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY));
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ReplacingUnlimitedApprovalWithFiniteApprovalEnforcesNewLimit() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertTrue(token.approve(spender, 1));

        _expectAllowanceError(spender, 1, 2);
        vm.prank(spender);
        token.transferFrom(address(this), bob, 2);
        assertEq(token.allowance(address(this), spender), 1);
        assertEq(token.balanceOf(bob), 0);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, 1));
        assertEq(token.allowance(address(this), spender), 0);
        _expectAllowanceError(spender, 0, 1);
        vm.prank(spender);
        token.transferFrom(address(this), bob, 1);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(bob), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 2);
    }

    function test_RevokedUnlimitedApprovalStaysRevokedAfterHolderIsRefunded() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY));
        assertTrue(token.approve(spender, 0));
        vm.prank(alice);
        assertTrue(token.transfer(address(this), SUPPLY));

        _expectAllowanceError(spender, 0, 1);
        vm.prank(spender);
        token.transferFrom(address(this), bob, 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_SelfApprovalAllowsOwnerToUseTransferFromAndIsConsumed() public {
        assertTrue(token.approve(address(this), 1));
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), address(this)), 0);
        _expectAllowanceError(address(this), 0, 1);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
    }

    function test_ZeroValueOperationsStillRejectInvalidAddresses() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(alice, address(0), 0);

        // These defensive branches require synthetic callers; no real transaction
        // has the zero address as its sender.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0)));
        vm.prank(address(0));
        token.transfer(alice, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(address(0));
        token.approve(spender, 0);

        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.allowance(address(0), spender), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_UnlimitedApprovalDoesNotAllowZeroRecipient() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), SUPPLY);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ContractRecipientDoesNotNeedAReceiverHook() public {
        SqueekRejectingRecipient recipient = new SqueekRejectingRecipient();
        assertTrue(token.transfer(address(recipient), 1));
        assertTrue(token.approve(spender, SUPPLY - 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(recipient), SUPPLY - 1));
        assertEq(token.balanceOf(address(recipient)), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TokensSentToTokenContractRemainPartOfSupply() public {
        // ERC-20 permits this recipient. Holding SQK at its own address is not a burn.
        assertTrue(token.transfer(address(token), SUPPLY));
        assertEq(token.balanceOf(address(token)), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_PayableCallsCannotMoveTokensOrSetApprovals() public {
        vm.deal(spender, 4);
        assertTrue(token.approve(spender, 1));
        bytes[] memory calls = new bytes[](4);
        calls[0] = "";
        calls[1] = abi.encodeCall(token.transfer, (alice, 0));
        calls[2] = abi.encodeCall(token.approve, (alice, 1));
        calls[3] = abi.encodeCall(token.transferFrom, (address(this), alice, 1));
        for (uint256 i; i < calls.length; ++i) {
            vm.prank(spender);
            (bool success,) = address(token).call{value: 1}(calls[i]);
            assertFalse(success, "nonpayable entry point accepted ETH");
        }
        assertEq(spender.balance, 4);
        assertEq(address(token).balance, 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(address(this), spender), 1);
        assertEq(token.allowance(spender, alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_TransferRoundTripRestoresBalancesAndLeavesApprovalsAlone(
        uint256 fundingSeed,
        uint256 amountSeed,
        uint256 approval
    ) public {
        uint256 funding = bound(fundingSeed, 0, SUPPLY);
        uint256 amount = bound(amountSeed, 0, funding);
        assertTrue(token.transfer(alice, funding));
        assertTrue(token.transfer(bob, SUPPLY - funding));
        vm.prank(alice);
        assertTrue(token.approve(spender, approval));
        vm.prank(alice);
        assertTrue(token.transfer(bob, amount));
        assertEq(token.balanceOf(bob), SUPPLY - funding + amount);
        vm.prank(bob);
        assertTrue(token.transfer(alice, amount));
        assertEq(token.balanceOf(alice), funding);
        assertEq(token.balanceOf(bob), SUPPLY - funding);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.allowance(alice, spender), approval);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_SplitDelegatedTransferMatchesSingleSpend(uint256 totalSeed, uint256 firstSeed) public {
        uint256 total = bound(totalSeed, 0, SUPPLY);
        uint256 first = bound(firstSeed, 0, total);
        Squeek singleSpend = new Squeek();
        assertTrue(token.approve(spender, total));
        assertTrue(singleSpend.approve(spender, total));

        vm.startPrank(spender);
        assertTrue(token.transferFrom(address(this), alice, first));
        assertTrue(token.transferFrom(address(this), alice, total - first));
        assertTrue(singleSpend.transferFrom(address(this), alice, total));
        vm.stopPrank();

        assertEq(token.balanceOf(alice), total);
        assertEq(token.balanceOf(alice), singleSpend.balanceOf(alice));
        assertEq(token.balanceOf(address(this)), singleSpend.balanceOf(address(this)));
        assertEq(token.balanceOf(address(this)), SUPPLY - total);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(singleSpend.allowance(address(this), spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(singleSpend.totalSupply(), SUPPLY);
    }

    function testFuzz_FailedSpendPreservesApprovalForLaterFunding(uint256 amountSeed, bool unlimited) public {
        uint256 amount = bound(amountSeed, 1, SUPPLY);
        uint256 approved = unlimited ? type(uint256).max : amount;
        vm.prank(alice);
        assertTrue(token.approve(spender, approved));

        // Repeat the failure: a failed debit must not consume an approval once,
        // or leave behind state that changes the next transaction's outcome.
        for (uint256 i; i < 2; ++i) {
            _expectBalanceError(alice, 0, amount);
            vm.prank(spender);
            token.transferFrom(alice, bob, amount);
            assertEq(token.allowance(alice, spender), approved);
            assertEq(token.balanceOf(alice), 0);
            assertEq(token.balanceOf(bob), 0);
        }
        assertTrue(token.transfer(alice, amount));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, amount));
        assertEq(token.allowance(alice, spender), unlimited ? type(uint256).max : 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ApprovalsAreIsolatedByOwnerAndSpender(uint256 allowanceA, uint256 allowanceB) public {
        assertTrue(token.transfer(alice, SUPPLY / 2));
        assertTrue(token.transfer(bob, SUPPLY / 2));
        vm.prank(alice);
        assertTrue(token.approve(spender, allowanceA));
        vm.prank(bob);
        assertTrue(token.approve(spender, allowanceB));
        vm.prank(alice);
        assertTrue(token.approve(otherSpender, type(uint256).max));

        // Revoking one edge in the owner/spender matrix must not affect others.
        vm.prank(alice);
        assertTrue(token.approve(spender, 0));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.allowance(alice, otherSpender), type(uint256).max);
        assertEq(token.allowance(bob, spender), allowanceB);
        assertEq(token.allowance(bob, otherSpender), 0);
        _expectAllowanceError(otherSpender, 0, 1);
        vm.prank(otherSpender);
        token.transferFrom(bob, alice, 1);

        vm.prank(otherSpender);
        assertTrue(token.transferFrom(alice, bob, 1));
        assertEq(token.balanceOf(alice), SUPPLY / 2 - 1);
        assertEq(token.balanceOf(bob), SUPPLY / 2 + 1);
        assertEq(token.allowance(alice, otherSpender), type(uint256).max);
        assertEq(token.allowance(bob, spender), allowanceB);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_TruncatedStateChangingCalldataRevertsWithoutChangingState(uint256 methodSeed, uint256 lengthSeed)
        public
    {
        assertTrue(token.transfer(spender, 1));
        assertTrue(token.approve(spender, 1));
        uint256 method = methodSeed % 3;
        bytes memory data = method == 0
            ? abi.encodeCall(token.transfer, (alice, 1))
            : method == 1
                ? abi.encodeCall(token.approve, (alice, 1))
                : abi.encodeCall(token.transferFrom, (address(this), alice, 1));
        uint256 length = bound(lengthSeed, 4, data.length - 1);
        bytes memory truncated = new bytes(length);
        for (uint256 i; i < length; ++i) {
            truncated[i] = data[i];
        }
        vm.prank(spender);
        (bool success,) = address(token).call(truncated);
        assertFalse(success, "incomplete arguments were accepted");
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.balanceOf(spender), 1);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(address(this), spender), 1);
        assertEq(token.allowance(spender, alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function _expectBalanceError(address holder, uint256 balance, uint256 amount) private {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, balance, amount));
    }

    function _expectAllowanceError(address caller, uint256 approved, uint256 amount) private {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, caller, approved, amount)
        );
    }
}

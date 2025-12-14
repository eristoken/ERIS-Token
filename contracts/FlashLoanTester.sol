// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20FlashMint.sol";

contract FlashLoanTester is IERC3156FlashBorrower {
    address public flashLoanProvider;

    constructor(address _flashLoanProvider) {
        flashLoanProvider = _flashLoanProvider;
    }

    function initiateFlashLoan(address token, uint256 amount) external {
        ERC20FlashMint(flashLoanProvider).flashLoan(
            IERC3156FlashBorrower(address(this)), // Cast to IERC3156FlashBorrower
            token,                                 // Token to flash mint
            amount,                                // Loan amount
            ""                                     // Data payload
        );
    }

    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata
    ) external override returns (bytes32) {
        require(msg.sender == flashLoanProvider, "Untrusted lender");
        require(initiator == address(this), "Untrusted initiator");

        // Approve the total repayment
        uint256 totalRepayment = amount + fee;
        IERC20(token).approve(msg.sender, totalRepayment);

        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }
}

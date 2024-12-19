// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract RebaseFeeManager is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;
    
    uint private _feeRateBips;
    uint public constant MAX_TEN_PERCENT_BIPS = 1000;
    EnumerableSet.AddressSet private _exemptions;
    
    function getFeeRateBips() external view returns (uint) {
        return _feeRateBips;
    }

    function setFeeRateBips(uint feeRateBips) onlyOwner external {
        require(feeRateBips <= MAX_TEN_PERCENT_BIPS, "Invalid Fee Rate");
        _feeRateBips = feeRateBips;
    }

    function addExemption(address token) onlyOwner external {
        _exemptions.add(token);
    }

    function removeExemption(address token) onlyOwner external {
        _exemptions.remove(token);
    }

    function hasExemption(address token) external view returns (bool) {
        return _exemptions.contains(token);
    }

    function getTokenFeeRateBips(address token) external view returns (uint) {
        if (_exemptions.contains(token)) {
            return 0;
        } else {
            return _feeRateBips;
        }
    }
}

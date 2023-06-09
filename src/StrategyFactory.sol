// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {Strategy} from "./Strategy.sol";

interface IStrategy {
    function setPerformanceFeeRecipient(address) external;

    function setKeeper(address) external;

    function setManagement(address) external;
}

contract StrategyFactory {
    event NewStrategy(address indexed strategy, address indexed asset);

    constructor(address _asset, string memory _name) {
        newStrategy(_asset, _name, msg.sender, msg.sender, msg.sender);
    }

    function newStrategy(
        address _asset,
        string memory _name
    ) public returns (address) {
        return
            newStrategy(_asset, _name, msg.sender, msg.sender, msg.sender);
    }

    function newStrategy(
        address _asset,
        string memory _name,
        address _performanceFeeRecipient,
        address _keeper,
        address _management
    ) public returns (address) {
        IStrategy _newStrategy = IStrategy(
            address(new Strategy(_asset, _name))
        );

        _newStrategy.setPerformanceFeeRecipient(_performanceFeeRecipient);

        _newStrategy.setKeeper(_keeper);

        _newStrategy.setManagement(_management);

        emit NewStrategy(address(_newStrategy), _asset);
        return address(_newStrategy);
    }
}

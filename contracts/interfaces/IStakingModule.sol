// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.7.6;

interface IStakingModule {
    function depositForUser(
        address _user,
        uint256 _amount,
        bool _skipLastDepositUpdate
    ) external;

    function deposit(uint256 _amount) external;

    function withdrawForUser(address _user, uint256 _shares) external;

    function withdrawAllForUser(address _user) external;

    function withdraw(uint256 _shares) external;

    function withdrawAll() external;

    function getCurrentUserInfo(address _user)
        external
        view
        returns (
            uint256,
            uint256,
            uint256
        );
}

// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.7.6;

interface IDateTime {
    function isLeapYear(uint16 year) external pure returns (bool);

    function leapYearsBefore(uint256 year) external pure returns (uint256);

    function getDaysInMonth(uint8 month, uint16 year)
        external
        pure
        returns (uint8);

    function getYear(uint256 timestamp) external pure returns (uint16);

    function getMonth(uint256 timestamp) external pure returns (uint8);

    function getDay(uint256 timestamp) external pure returns (uint8);

    function toTimestamp(
        uint16 year,
        uint8 month,
        uint8 day,
        uint8 hour,
        uint8 minute,
        uint8 second
    ) external pure returns (uint256 timestamp);
}

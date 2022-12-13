// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract PactGroup {
    //membership list
    // mapping(string => address[]) public membershipLists;
    // mapping(string => mapping(address => bool)) public listAdmin;

    // //modifiers
    // modifier isListAdmin(string memory listName) {
    //     require(listAdmin[listName][msg.sender], "Unauthorized");
    //     _;
    // }

    // function createMembershipList(
    //     string calldata listName_,
    //     address[] calldata members_
    // ) external payable {
    //     require(membershipLists[listName_].length == 0 && members_.length > 0);
    //     if (bytes(listName_).length < 12) {
    //         require(
    //             msg.value >=
    //                 (donationMaxAmount / 10 ** (bytes(listName_).length)),
    //             "Insufficient amount"
    //         );
    //         donationAccount.transfer(msg.value);
    //     }

    //     listAdmin[listName_][msg.sender] = true;
    //     addMembersToList(listName_, members_);
    //     emit logMembershipListCreated(msg.sender, listName_);
    // }

    // function addAdminForList(
    //     string calldata listName_,
    //     address newAdmin_
    // ) external isListAdmin(listName_) {
    //     listAdmin[listName_][newAdmin_] = true;
    // }

    // /**Function to remove self or a member for a given list */
    // function removeFromList(
    //     string calldata listName_,
    //     uint indexToRemove,
    //     address memberToRemove_
    // ) external {
    //     require(
    //         listAdmin[listName_][msg.sender] || memberToRemove_ == msg.sender,
    //         "Unauthorized"
    //     );
    //     uint listLength = membershipLists[listName_].length;
    //     require(
    //         indexToRemove < listLength &&
    //             membershipLists[listName_][indexToRemove] == memberToRemove_
    //     );
    //     if (indexToRemove < listLength - 1 && listLength > 1) {
    //         //not the last element
    //         membershipLists[listName_][indexToRemove] = membershipLists[
    //             listName_
    //         ][listLength - 1];
    //     }
    //     membershipLists[listName_].pop();
    // }

    // function addMembersToList(
    //     string calldata listName_,
    //     address[] calldata members_
    // ) public isListAdmin(listName_) {
    //     for (uint i = 0; i < members_.length; i++) {
    //         if (members_[i] != address(0)) {
    //             membershipLists[listName_].push(members_[i]);
    //         }
    //     }
    // }

    // function getListMembers(
    //     string calldata listName
    // ) external view returns (address[] memory) {
    //     return membershipLists[listName];
    // }
}

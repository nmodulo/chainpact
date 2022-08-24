import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import { ethers } from "hardhat";

describe("SimpleEmployment", function () {
  

  describe("Onboarding", function() {
    it("should allow")
  })
});

/**
 * 
 * Should return the contract data hash correctly
 * Should return the contract signer correctly given a signature and signing data
 * 
 * should allow employer to send signature and signing date
 * should not allow any other account to send employer signature
 * should allow retracting offer
 * should set the start variable after starting
 * should not allow accounts outside approvers to access this
 * 
 * should allow employee to send signature and signing date
 * should not allow other accounts to send employee sign
 * 
 * only employee or delegate allowed to raise dispute
 * only parties allowed to pause
 * 
 * 
 */

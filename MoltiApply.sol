/*
███╗   ███╗ ██████╗ ██╗  ████████╗██╗     
████╗ ████║██╔═══██╗██║  ╚══██╔══╝██║     
██╔████╔██║██║   ██║██║     ██║   ██║     
██║╚██╔╝██║██║   ██║██║     ██║   ██║     
██║ ╚═╝ ██║╚██████╔╝███████╗██║   ██║     
╚═╝     ╚═╝ ╚═════╝ ╚══════╝╚═╝   ╚═╝     
 █████╗ ██████╗ ██████╗ ██╗  ██╗   ██╗    
██╔══██╗██╔══██╗██╔══██╗██║  ╚██╗ ██╔╝    
███████║██████╔╝██████╔╝██║   ╚████╔╝     
██╔══██║██╔═══╝ ██╔═══╝ ██║    ╚██╔╝      
██║  ██║██║     ██║     ███████╗██║       
╚═╝  ╚═╝╚═╝     ╚═╝     ╚══════╝╚═╝   
*/
// SPDX-License-Identifier: MIT
/**
MIT License
Copyright (c) 2020 Openlaw
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
 */
pragma solidity 0.7.4;
pragma experimental ABIEncoderV2;

interface IERC20ApproveTransfer { // interface for erc20 approve/transfer
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
}

interface IMolochProposal { // interface for moloch dao proposal
    function cancelProposal(uint256 proposalId) external;
    
    function submitProposal(
        address applicant,
        uint256 sharesRequested,
        uint256 lootRequested,
        uint256 tributeOffered,
        address tributeToken,
        uint256 paymentRequested,
        address paymentToken,
        string calldata details
    ) external returns (uint256);
    
    function withdrawBalance(address token, uint256 amount) external;
}

contract ReentrancyGuard { // call wrapper for reentrancy check
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}

contract MoltiApply is ReentrancyGuard {
    address public moloch; // parent moloch dao for proposals 
    mapping(uint256 => Proposal) public props; // proposalId => Proposal
    mapping(address => uint256) public tokens; // tokens supported
    
    struct Proposal {
        address proposer;
        address tributeToken;
        uint256 tributeOffered;
    }

    event Propose(address indexed proposer, uint256 proposalId);
    event WithdrawProposal(address indexed proposer, uint256 proposalId);

    constructor(address[] memory _approvedTokens, address _moloch) {
        for (uint256 i = 0; i < _approvedTokens.length; i++) {
            IERC20ApproveTransfer(_approvedTokens[i]).approve(_moloch, uint256(-1));
            tokens[_approvedTokens[i]];
        }
        
        moloch = _moloch;
    }
    
    function propose(
        address[] memory applicant,
        uint256[] memory sharesRequested,
        uint256[] memory lootRequested,
        uint256[] memory tributeOffered,
        address[] memory tributeToken,
        uint256[] memory paymentRequested,
        address[] memory paymentToken,
        string[] memory details
    ) public nonReentrant { 
        for (uint256 i = 0; i < applicant.length; i++) {
            uint256 proposalId = IMolochProposal(moloch).submitProposal(
            applicant[i],
            sharesRequested[i],
            lootRequested[i],
            tributeOffered[i],
            tributeToken[i],
            paymentRequested[i],
            paymentToken[i],
            details[i]
        );
            props[proposalId] = Proposal(msg.sender, tributeToken[i], tributeOffered[i]);

            emit Propose(msg.sender, proposalId);
        }
    }
    
    function cancelProposal(uint256 proposalId) external nonReentrant { // proposer can cancel proposal & withdraw funds 
        Proposal storage proposal = props[proposalId];
        require(msg.sender == proposal.proposer, "MoltiApply::!proposer");
        address tributeToken = proposal.tributeToken;
        uint256 tributeOffered = proposal.tributeOffered;
        
        IMolochProposal(moloch).cancelProposal(proposalId); // cancel proposal in moloch
        IMolochProposal(moloch).withdrawBalance(tributeToken, tributeOffered); // withdraw proposal funds from moloch
        IERC20ApproveTransfer(tributeToken).transfer(msg.sender, tributeOffered); // redirect funds to proposer
        
        emit WithdrawProposal(msg.sender, proposalId);
    }
    
    function drawProposal(uint256 proposalId) external nonReentrant { // if proposal fails, withdraw back to proposer
        Proposal storage proposal = props[proposalId];
        require(msg.sender == proposal.proposer, "MoltiApply::!proposer");
        address tributeToken = proposal.tributeToken;
        uint256 tributeOffered = proposal.tributeOffered;
        
        IMolochProposal(moloch).withdrawBalance(tributeToken, tributeOffered); // withdraw proposal funds from moloch
        IERC20ApproveTransfer(tributeToken).transfer(msg.sender, tributeOffered); // redirect funds to proposer
        
        emit WithdrawProposal(msg.sender, proposalId);
    }
}

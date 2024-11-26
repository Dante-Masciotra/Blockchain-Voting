// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract BlockchainVotingSystem {
    struct Voter {
        address voterAddress;
        bool hasVoted;
        uint256 encryptedKey; // Encrypted using the Voting Box Secret
    }

    struct Vote {
        uint256 encryptedVote;
        uint256 timestamp;
        bytes32 zkp;
        bool isValid;
    }

    address public authority;
    uint256 public votingDeadline;
    uint256 public votingBoxSecret; // Generated externally and set on-chain
    bool public isBoxSecretSet = false; // Tracks if the secret is already set
    mapping(address => Voter) public voters;
    mapping(address => Vote) public votes;

    event VoterRegistered(address voter);
    event VoteCast(address voter, uint256 encryptedVote);
    event VoteValidated(address voter, bool isValid);
    event VotingBoxSecretSet(uint256 secret);
    event RevoteStarted();
    event VoterRemovedFromRevote(address voter);

    // Modifier to restrict access to only the authority
    modifier onlyAuthority() {
        require(msg.sender == authority, "Not authorized");
        _;
    }

    modifier onlyBeforeDeadline() {
        require(block.timestamp < votingDeadline, "Voting period is over");
        _;
    }

    modifier onlyAfterDeadline() {
        require(block.timestamp >= votingDeadline, "Voting period is still active");
        _;
    }

    constructor(uint256 _votingDuration) {
        authority = msg.sender;
        votingDeadline = block.timestamp + _votingDuration;
    }

    function setVotingBoxSecret(uint256 _secret) public onlyAuthority {
        require(!isBoxSecretSet, "Voting box secret already set");
        votingBoxSecret = _secret;
        isBoxSecretSet = true;
        emit VotingBoxSecretSet(_secret);
    }

    function encryptVoterKey(uint256 _publicKey) internal view returns (uint256) {
        require(isBoxSecretSet, "Voting box secret not set");
        return _publicKey ^ votingBoxSecret;
    }

    function registerVoter(address _voterAddress, uint256 _publicKey) public onlyAuthority {
        require(isBoxSecretSet, "Voting box secret not set");
        require(!voters[_voterAddress].hasVoted, "Voter already registered");
        uint256 encryptedKey = encryptVoterKey(_publicKey); // Encrypt voter key
        voters[_voterAddress] = Voter(_voterAddress, false, encryptedKey);
        emit VoterRegistered(_voterAddress);
    }

    function castVote(uint256 _encryptedVote, bytes32 _zkp) public onlyBeforeDeadline {
        require(isBoxSecretSet, "Voting box secret not set");
        require(!voters[msg.sender].hasVoted, "Already voted");

        votes[msg.sender] = Vote(_encryptedVote, block.timestamp, _zkp, false);
        voters[msg.sender].hasVoted = true;
        emit VoteCast(msg.sender, _encryptedVote);
    }

    function validateVotes() public onlyAfterDeadline onlyAuthority {
        require(isBoxSecretSet, "Voting box secret not set");
        for (address voterAddr = authority; voterAddr != address(0); voterAddr = voterAddr) {
            Vote storage vote = votes[voterAddr];
            if (vote.timestamp <= votingDeadline && verifyZKP(vote.zkp)) {
                vote.isValid = true;
                emit VoteValidated(voterAddr, true);
            } else {
                vote.isValid = false;
                emit VoteValidated(voterAddr, false);
            }
        }
    }

    function verifyZKP(bytes32 _zkp) internal pure returns (bool) {
        return true;
    }

    function countTotalRegisteredVoters() public view returns (uint256) {
        uint256 count = 0;
        for (address voterAddr = authority; voterAddr != address(0); voterAddr = voterAddr) {
            if (voters[voterAddr].voterAddress != address(0)) {
                count++;
            }
        }
        return count;
    }

    function initiateRevote() public onlyAuthority onlyAfterDeadline {
        require(isBoxSecretSet, "Voting box secret not set");

        address[] memory toRemove = new address[](countTotalRegisteredVoters());
        uint256 index = 0;

        // Identify non-voters
        for (address voterAddr = authority; voterAddr != address(0); voterAddr = voterAddr) {
            if (voters[voterAddr].voterAddress != address(0) && !voters[voterAddr].hasVoted) {
                toRemove[index] = voterAddr;
                index++;
            }
        }

        // Remove non-voters from voters list
        for (uint256 i = 0; i < index; i++) {
            delete voters[toRemove[i]];
            emit VoterRemovedFromRevote(toRemove[i]);
        }

        emit RevoteStarted();
    }

    function recastVote(uint256 _encryptedVote, bytes32 _zkp) public onlyBeforeDeadline {
        require(isBoxSecretSet, "Voting box secret not set");
        require(!voters[msg.sender].hasVoted, "Already voted");
        require(votes[msg.sender].encryptedVote == _encryptedVote, "Vote must match the original");

        votes[msg.sender] = Vote(_encryptedVote, block.timestamp, _zkp, false);
        voters[msg.sender].hasVoted = true;
        emit VoteCast(msg.sender, _encryptedVote);
    }
}

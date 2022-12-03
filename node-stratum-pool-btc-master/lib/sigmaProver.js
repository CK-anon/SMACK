var EC = require('elliptic');
const { Keccak } = require('sha3');
require('dotenv').config();
const BN = require('bn.js');
var assert = require('assert');
var crypto = require('crypto');
const hash = new Keccak(256);




var SigmaProver = module.exports = function SigmaProver(_numRounds){
    this.curve = EC.curves.secp256k1.curve;
    this.numRounds = _numRounds;
    this.currentRound = 0;
    this.commitmentsX = [];
    this.commitmentsY = [];
    this.random_nonces = [];
    this.generator = this.curve.g;
    this.groupOrder = new BN("115792089237316195423570985008687907852837564279074904382605163141518161494337", 10);
    
    var priv_key = process.env.PRIV_KEY;
    this.sk = new BN(priv_key, 16);
    
    this.pk = this.generator.mul(this.sk);
    // var pk_encoded = this.pk.getX().toString(16) + this.pk.getY().toString(16);
    // console.log("PKX:", this.pk.getX().toString(10))
    // console.log("PKY:", this.pk.getY().toString(10))
    
    // this.address = hash.update(Buffer.from(pk_encoded, 'hex')).digest('hex');

    for (let i = 0; i < this.numRounds; i++) {
        var random_k = new BN(crypto.randomBytes(32));
        this.random_nonces.push(random_k)
        console.log(random_k.toString(10))
        commitment_i = this.generator.mul(random_k);
        this.commitmentsX.push(commitment_i.getX().toString(10));
        this.commitmentsY.push(commitment_i.getY().toString(10));
    }
    
    this.getResponse = function(challenge) {
        // console.log(challenge.mul(new BN(3)).add(new BN(2)).umod(this.groupOrder).toString(10))
        var a = this.sk.mul(new BN(challenge));
        var b = a.add(this.random_nonces[this.currentRound]);
        return b.umod(this.groupOrder).toString('hex', 32)
    }
    
    this.getCommitments = function() {
        // console.log(this.commitmentsX, this.commitmentsY)
        return [this.commitmentsX, this.commitmentsY, this.pk.getX().toString(10), this.pk.getY().toString(10)];
    }

    this.updateRound = function(updatedRound) {
        // console.log(this.commitmentsX, this.commitmentsY)
        this.currentRound = updatedRound;
    }
}

// sp = new SigmaProver(5);
// console.log(sp.getResponse(new BN("43000047899898303925802334608717760678591555636058478695802810556668006975190", 10), 0));
// console.log(sp.getCommitments())
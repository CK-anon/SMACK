var events = require('events');
var crypto = require('crypto');

var bignum = require('bignum');
const BN = require('bn.js');

var util = require('./util.js');
var blockTemplate = require('./blockTemplate.js');
var sigmaProver = require('./sigmaProver.js');
// var blockchain = require('./blockchain.js');
const { BADNAME } = require('dns');
const fs = require('fs');



//Unique extranonce per subscriber
var ExtraNonceCounter = function(configInstanceId){

    var instanceId = configInstanceId || crypto.randomBytes(4).readUInt32LE(0);
    var counter = instanceId << 27;

    this.next = function(){
        var extraNonce = util.packUInt32BE(Math.abs(counter++));
        return 'deadc0de';
        // return extraNonce.toString('hex');
    };

    this.size = 4; //bytes
};

//Unique job per new block template
var JobCounter = function(){
    var counter = 0;

    this.next = function(){
        counter++;
        if (counter % 0xffff === 0)
            counter = 1;
        return this.cur();
    };

    this.cur = function () {
        return counter.toString(16);
    };
};


/**
 * Emits:
 * - newBlock(blockTemplate) - When a new block (previously unknown to the JobManager) is added, use this event to broadcast new jobs
 * - share(shareData, blockHex) - When a worker submits a share. It will have blockHex if a block was found
**/
var JobManager = module.exports = function JobManager(options){

    

    //private members

    var _this = this;
    var jobCounter = new JobCounter();
    _this.totalRounds = 5;
    
    var shareMultiplier = algos[options.coin.algorithm].multiplier;
    
    //public members
    // this.blockchain = new blockchain(_this.totalRounds);
    this.sigmaProver = new sigmaProver(_this.totalRounds); // 5 rounds
    this.responseBlocks = []
    
    console.log(this.sigmaProver.getCommitments())
    
    // const prompt = require('prompt-sync')({sigint: true});
    // const input_randomness = prompt('Enter challenge randomness?');
    // console.log('You entered:', input_randomness)

    randomness_file = '../randomness.txt'
    while (!fs.existsSync(randomness_file)) {
    }

    const data = fs.readFileSync(randomness_file,
            {encoding:'utf8', flag:'r'});

    this.challengeRandomness = new BN(data, 'hex'); // manually hardcoded, automate later
    console.log("### Randomness ###:", this.challengeRandomness.toString('hex'))

    this.currentRound = 0;
    this.sigmaProver.updateRound(this.currentRound);

    this.extraNonceCounter = new ExtraNonceCounter(options.instanceId);
    // this.extraNoncePlaceholder = new Buffer('f000000ff111111f', 'hex');
    this.extraNoncePlaceholder = new Buffer('f000000faa', 'hex');
    this.extraNonce2Size = this.extraNoncePlaceholder.length - this.extraNonceCounter.size;

    this.currentJob;
    this.validJobs = {};

    var hashDigest = algos[options.coin.algorithm].hash(options.coin);

    var coinbaseHasher = (function(){
        switch(options.coin.algorithm){
            case 'keccak':
            case 'fugue':
            case 'groestl':
                if (options.coin.normalHashing === true)
                    return util.sha256d;
                else
                    return util.sha256;
            default:
                return util.sha256d;
        }
    })();


    var blockHasher = (function () {
        switch (options.coin.algorithm) {
            case 'scrypt':
                if (options.coin.reward === 'POS') {
                    return function (d) {
                        return util.reverseBuffer(hashDigest.apply(this, arguments));
                    };
                }
            case 'scrypt-jane':
                if (options.coin.reward === 'POS') {
                    return function (d) {
                        return util.reverseBuffer(hashDigest.apply(this, arguments));
                    };
                }
            case 'scrypt-n':
                return function (d) {
                    return util.reverseBuffer(util.sha256d(d));
                };
            default:
                return function () {
                    return util.reverseBuffer(hashDigest.apply(this, arguments));
                };
        }
    })();

    this.getRotatedJobParams = function() {
        var tmpBlockTemplate = new blockTemplate(
            jobCounter.next(),
            _this.currentJob.rpcData,
            options.poolAddressScript,
            _this.extraNoncePlaceholder,
            options.coin.reward,
            options.coin.txMessages,
            options.recipients,
            options.network,
            _this.sigmaProver,
            _this.challengeRandomness.toString('hex', 32)

        );
        _this.currentJob = tmpBlockTemplate;
        _this.validJobs = {}
        _this.validJobs[tmpBlockTemplate.jobId] = tmpBlockTemplate;
        // console.log(_this.currentJob.getJobParams());
        return _this.currentJob.getJobParams();
    }

    this.updateCurrentJob = function(rpcData){

        var tmpBlockTemplate = new blockTemplate(
            jobCounter.next(),
            rpcData,
            options.poolAddressScript,
            _this.extraNoncePlaceholder,
            options.coin.reward,
            options.coin.txMessages,
            options.recipients,
            options.network,
            _this.sigmaProver,
            _this.challengeRandomness.toString('hex', 32)
        );

        _this.currentJob = tmpBlockTemplate;

        _this.emit('updatedBlock', tmpBlockTemplate, true);

        _this.validJobs[tmpBlockTemplate.jobId] = tmpBlockTemplate;

    };

    //returns true if processed a new block
    this.processTemplate = function(rpcData){

        /* Block is new if A) its the first block we have seen so far or B) the blockhash is different and the
           block height is greater than the one we have */
        var isNewBlock = typeof(_this.currentJob) === 'undefined';
        if  (!isNewBlock && _this.currentJob.rpcData.previousblockhash !== rpcData.previousblockhash){
            isNewBlock = true;

            //If new block is outdated/out-of-sync than return
            if (rpcData.height < _this.currentJob.rpcData.height)
                return false;
        }

        if (!isNewBlock) return false;


        var tmpBlockTemplate = new blockTemplate(
            jobCounter.next(),
            rpcData,
            options.poolAddressScript,
            _this.extraNoncePlaceholder,
            options.coin.reward,
            options.coin.txMessages,
            options.recipients,
            options.network,
            _this.sigmaProver,
            _this.challengeRandomness.toString('hex', 32)
        );

        this.currentJob = tmpBlockTemplate;

        this.validJobs = {};
        _this.emit('newBlock', tmpBlockTemplate);

        this.validJobs[tmpBlockTemplate.jobId] = tmpBlockTemplate;

        return true;

    };

    this.processShare = function(jobId, previousDifficulty, difficulty, extraNonce1, extraNonce2, nTime, nonce, ipAddress, port, workerName){
        var shareError = function(error){
            _this.emit('share', {
                job: jobId,
                ip: ipAddress,
                worker: workerName,
                difficulty: difficulty,
                error: error[1]
            });
            return {error: error, result: null};
        };

        var submitTime = Date.now() / 1000 | 0;

        if (extraNonce2.length / 2 !== _this.extraNonce2Size)
            return shareError([20, 'incorrect size of extranonce2']);

        var job = this.validJobs[jobId];

        if (typeof job === 'undefined' || job.jobId != jobId ) {
            _this.emit('log', 'debug', this.validJobs);
            return shareError([21, 'job not found, got ' + jobId ]);
        }

        if (nTime.length !== 8) {
            return shareError([20, 'incorrect size of ntime']);
        }

        var nTimeInt = parseInt(nTime, 16);
        if (nTimeInt < job.rpcData.curtime || nTimeInt > submitTime + 7200) {
            return shareError([20, 'ntime out of range']);
        }

        if (nonce.length !== 8) {
            return shareError([20, 'incorrect size of nonce']);
        }

        if (!job.registerSubmit(extraNonce1, extraNonce2, nTime, nonce)) {
            return shareError([22, 'duplicate share']);
        }


        var extraNonce1Buffer = new Buffer(extraNonce1, 'hex');
        var extraNonce2Buffer = new Buffer(extraNonce2, 'hex');

        var coinbaseBuffer = job.serializeCoinbase(extraNonce1Buffer, extraNonce2Buffer);
        var coinbaseHash = coinbaseHasher(coinbaseBuffer);

        var merkleRoot = util.reverseBuffer(job.merkleTree.withFirst(coinbaseHash)).toString('hex');

        var headerBuffer = job.serializeHeader(merkleRoot, nTime, nonce);
        var headerHash = hashDigest(headerBuffer, nTimeInt);
        var headerBigNum = bignum.fromBuffer(headerHash, {endian: 'little', size: 32});

        var blockHashInvalid;
        var blockHash;
        var blockHex;

        var shareDiff = diff1 / headerBigNum.toNumber() * shareMultiplier;

        var blockDiffAdjusted = job.difficulty * shareMultiplier;

        //Check if share is a block candidate (matched network difficulty)
        if (job.target.ge(headerBigNum)){
            blockHex = job.serializeBlock(headerBuffer, coinbaseBuffer).toString('hex');
            if (options.coin.algorithm === 'blake' || options.coin.algorithm === 'neoscrypt') {                
                blockHash = util.reverseBuffer(util.sha256d(headerBuffer, nTime)).toString('hex');
            }
            else {
            	blockHash = blockHasher(headerBuffer, nTime).toString('hex');
            }
        }
        else {
            if (options.emitInvalidBlockHashes)
                blockHashInvalid = util.reverseBuffer(util.sha256d(headerBuffer)).toString('hex');

            //Check if share didn't reached the miner's difficulty)
            if (shareDiff / difficulty < 0.99){

                //Check if share matched a previous difficulty from before a vardiff retarget
                if (previousDifficulty && shareDiff >= previousDifficulty){
                    difficulty = previousDifficulty;
                }
                else{
                    return shareError([23, 'low difficulty share of ' + shareDiff]);
                }

            }
        }

        _this.emit('log', 'debug', 'SigmaProver Round: ' + _this.currentRound);

            _this.currentRound += 1;
            _this.challengeRandomness.iadd(new BN(1));
            //TODO : do not rely on extranonce2 size being 1 byte, automate
            var responseBlock = ['0x'+ job.generationTransaction[0].toString('hex'), '0xdeadc0de', '0x'+extraNonce2, 
                                    '0x'+job.generationTransaction[1].toString('hex'), '0x'+nonce, 
                                    '0x'+job.rpcData.bits, '0x'+util.packUInt32BE(job.rpcData.curtime).toString('hex'),
                                    '0x'+job.rpcData.previousblockhash, '0x'+util.packInt32BE(job.rpcData.version).toString('hex')]
            _this.responseBlocks.push(responseBlock);
        

        if (_this.currentRound < _this.totalRounds ) {
            _this.sigmaProver.updateRound(_this.currentRound);
        }
        


        _this.emit('share', {
            job: jobId,
            ip: ipAddress,
            port: port,
            worker: workerName,
            height: job.rpcData.height,
            blockReward: job.rpcData.coinbasevalue,
            difficulty: difficulty,
            shareDiff: shareDiff.toFixed(8),
            blockDiff : blockDiffAdjusted,
            blockDiffActual: job.difficulty,
            blockHash: blockHash,
            blockHashInvalid: blockHashInvalid,
            challenge: job.challenge.toString('hex'),
            sigmaResponse: job.sigmaResponse,
            nonce: nonce,
            extraNonce2: extraNonce2,
            blockContents: job.blockContents,
            coinbaseBuffer: coinbaseBuffer,
            coinbaseHash: coinbaseHash,
            merkleRoot: merkleRoot,
            headerBuffer: headerBuffer,
            headerHash: headerHash

        }, blockHex);
        
        if (_this.responseBlocks.length == _this.totalRounds) {
            // _this.emit('log', 'info', _this.responseBlocks);
            result = JSON.stringify(_this.responseBlocks)
            fs.writeFileSync('../result.json', result);
            console.log("#################### Written #################")
        }

        return {result: true, error: null, blockHash: blockHash};
    };
};
JobManager.prototype.__proto__ = events.EventEmitter.prototype;

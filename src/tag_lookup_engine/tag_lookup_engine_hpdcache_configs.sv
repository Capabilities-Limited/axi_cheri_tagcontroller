function automatic hpdcache_pkg::hpdcache_user_cfg_t root_hpdcache_user_cfg(int unsigned nRequesters);
  hpdcache_pkg::hpdcache_user_cfg_t userCfg;
  userCfg.nRequesters = nRequesters;
  userCfg.paWidth = 49;
  userCfg.wordWidth = 1;
  userCfg.wordUserWidth = 1;
  userCfg.sets = 8;
  userCfg.ways = 4;
  userCfg.clWords = 256;
  userCfg.reqWords = 64'd4;
  userCfg.reqTransIdWidth = 6;
  userCfg.reqSrcIdWidth = 2;  // Up to 4 requesters
  userCfg.victimSel = hpdcache_pkg::HPDCACHE_VICTIM_PLRU;
  userCfg.dataWaysPerRamWord = 4;
  userCfg.dataSetsPerRam = 256;
  userCfg.dataRamByteEnable = 1'b1; // XXX TODO check the 1'b0 option
  userCfg.accessWords = 32;
  userCfg.mshrSets = 1;
  userCfg.mshrWays = 4;
  userCfg.mshrWaysPerRamWord = 2;
  userCfg.mshrSetsPerRam = 32;
  userCfg.mshrRamByteEnable = 1'b1; // XXX TODO check the 1'b0 option
  userCfg.mshrUseRegbank = 1;
  userCfg.cbufEntries = 8;
  userCfg.refillCoreRspFeedthrough = 1'b1;
  userCfg.refillFifoDepth = 16;
  userCfg.wbufDirEntries = 8;
  userCfg.wbufDataEntries = 4;
  userCfg.wbufWords = 2;
  userCfg.wbufTimecntWidth = 3;
  userCfg.rtabEntries = 4;
  userCfg.flushEntries = 4;
  userCfg.flushFifoDepth = 2;
  userCfg.memAddrWidth = 64;
  userCfg.memIdWidth = 4;
  userCfg.memDataWidth = 64;
  userCfg.wtEn = 1'b0;
  userCfg.wbEn = 1'b1;
  userCfg.lowLatency = 1'b0;
  userCfg.userEn = 1'b0;
  userCfg.capAmoEn = 1'b0;
  userCfg.eccEn = 1'b0;  /*FIXME add additional CVA6 parameter*/
  userCfg.eccScrubberEn = 1'b0;  /*FIXME: add additional CVA6 parameter*/
  return userCfg;
endfunction

function automatic hpdcache_pkg::hpdcache_user_cfg_t leaf_hpdcache_user_cfg(int unsigned nRequesters);
  hpdcache_pkg::hpdcache_user_cfg_t userCfg;
  userCfg.nRequesters = nRequesters;
  userCfg.paWidth = 49;
  userCfg.wordWidth = 1;
  userCfg.wordUserWidth = 1;
  userCfg.sets = 128;
  userCfg.ways = 4;
  userCfg.clWords = 256;
  userCfg.reqWords = 64'd4;
  userCfg.reqTransIdWidth = 6;
  userCfg.reqSrcIdWidth = 2;  // Up to 4 requesters
  userCfg.victimSel = hpdcache_pkg::HPDCACHE_VICTIM_PLRU;
  userCfg.dataWaysPerRamWord = 4;
  userCfg.dataSetsPerRam = 128;
  userCfg.dataRamByteEnable = 1'b1; // XXX TODO check the 1'b0 option
  userCfg.accessWords = 32;
  userCfg.mshrSets = 1;
  userCfg.mshrWays = 4;
  userCfg.mshrWaysPerRamWord = 2;
  userCfg.mshrSetsPerRam = 32;
  userCfg.mshrRamByteEnable = 1'b1; // XXX TODO check the 1'b0 option
  userCfg.mshrUseRegbank = 1;
  userCfg.cbufEntries = 8;
  userCfg.refillCoreRspFeedthrough = 1'b1;
  userCfg.refillFifoDepth = 16;
  userCfg.wbufDirEntries = 8;
  userCfg.wbufDataEntries = 4;
  userCfg.wbufWords = 2;
  userCfg.wbufTimecntWidth = 3;
  userCfg.rtabEntries = 4;
  userCfg.flushEntries = 4;
  userCfg.flushFifoDepth = 2;
  userCfg.memAddrWidth = 64;
  userCfg.memIdWidth = 4;
  userCfg.memDataWidth = 64;
  userCfg.wtEn = 1'b0;
  userCfg.wbEn = 1'b1;
  userCfg.lowLatency = 1'b0;
  userCfg.userEn = 1'b0;
  userCfg.capAmoEn = 1'b0;
  userCfg.eccEn = 1'b0;  /*FIXME add additional CVA6 parameter*/
  userCfg.eccScrubberEn = 1'b0;  /*FIXME: add additional CVA6 parameter*/
  return userCfg;
endfunction

import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Char "mo:base/Char";
import Cycles "mo:base/ExperimentalCycles";
import Float "mo:base/Float";
import HashMap "mo:base/HashMap";
import Int "mo:base/Int";
import Int64 "mo:base/Int64";
import Int8 "mo:base/Int8";
import Iter "mo:base/Iter";
import List "mo:base/List";
import Nat "mo:base/Nat";
import Nat32 "mo:base/Nat32";
import Nat64 "mo:base/Nat64";
import Nat8 "mo:base/Nat8";
import Option "mo:base/Option";
import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Text "mo:base/Text";
import Time "mo:base/Time";

import Cap "mo:cap/Cap";
import Encoding "mo:encoding/Binary";

import AID "motoko/util/AccountIdentifier";
import ExtAllowance "motoko/ext/Allowance";
import ExtCommon "motoko/ext/Common";
import ExtCore "motoko/ext/Core";
import ExtNonFungible "motoko/ext/NonFungible";
import SVG "svg";
import Env "env";

// TODO: account for transactions that may fail to send items along with characters

actor class ObsidianTears() = this {

  // Types
  type Time = Time.Time;
  type AccountIdentifier = ExtCore.AccountIdentifier;
  type SubAccount = ExtCore.SubAccount;
  type User = ExtCore.User;
  type Balance = ExtCore.Balance;
  type TokenIdentifier = ExtCore.TokenIdentifier;
  type TokenIndex = ExtCore.TokenIndex;
  type Extension = ExtCore.Extension;
  type CommonError = ExtCore.CommonError;
  type BalanceRequest = ExtCore.BalanceRequest;
  type BalanceResponse = ExtCore.BalanceResponse;
  type TransferRequest = ExtCore.TransferRequest;
  type TransferResponse = ExtCore.TransferResponse;
  type AllowanceRequest = ExtAllowance.AllowanceRequest;
  type ApproveRequest = ExtAllowance.ApproveRequest;
  type Metadata = ExtCommon.Metadata;
  type NotifyService = ExtCore.NotifyService;
  type MintingRequest = {
    to : AccountIdentifier;
    asset : Nat32;
  };

  //Marketplace
  type Transaction = {
    token : TokenIdentifier;
    seller : Principal;
    price : Nat64;
    buyer : AccountIdentifier;
    time : Time;
  };
  type Settlement = {
    seller : Principal;
    price : Nat64;
    subaccount : SubAccount;
    buyer : AccountIdentifier;
  };
  type Listing = {
    seller : Principal;
    price : Nat64;
    locked : ?Time;
  };
  type ListRequest = {
    token : TokenIdentifier;
    from_subaccount : ?SubAccount;
    price : ?Nat64;
  };
  type AccountBalanceArgs = { account : AccountIdentifier };
  type ICPTs = { e8s : Nat64 };

  type SendArgs = {
    memo : Nat64;
    amount : ICPTs;
    fee : ICPTs;
    from_subaccount : ?SubAccount;
    to : AccountIdentifier;
    created_at_time : ?Time;
  };
  let LEDGER_CANISTER = actor "ryjl3-tyaaa-aaaaa-aaaba-cai" : actor {
    send_dfx : shared SendArgs -> async Nat64;
    account_balance_dfx : shared query AccountBalanceArgs -> async ICPTs;
  };

  //Cap
  type CapDetailValue = {
    #I64 : Int64;
    #U64 : Nat64;
    #Vec : [CapDetailValue];
    #Slice : [Nat8];
    #Text : Text;
    #True;
    #False;
    #Float : Float;
    #Principal : Principal;
  };
  type CapEvent = {
    time : Nat64;
    operation : Text;
    details : [(Text, CapDetailValue)];
    caller : Principal;
  };
  type CapIndefiniteEvent = {
    operation : Text;
    details : [(Text, CapDetailValue)];
    caller : Principal;
  };
  //EXTv2 SALE
  private stable var _disbursementsState : [(TokenIndex, AccountIdentifier, SubAccount, Nat64)] = [];
  private stable var _nextSubAccount : Nat = 0;
  private var _disbursements : List.List<(TokenIndex, AccountIdentifier, SubAccount, Nat64)> = List.fromArray(_disbursementsState);

  //CAP
  private stable var capRootBucketId : ?Text = null;
  let CapService = Cap.Cap(?"lj532-6iaaa-aaaah-qcc7a-cai", capRootBucketId);
  private stable var _capEventsState : [CapIndefiniteEvent] = [];
  private var _capEvents : List.List<CapIndefiniteEvent> = List.fromArray(_capEventsState);
  private stable var _runHeartbeat : Bool = true;

  type AssetHandle = Text;
  type Asset = {
    id : Nat32;
    ctype : Text;
    name : Text;
    canister : Text;
  };
  //OBSIDIAN TEARS
  let _gameActor = actor (Env.getGameCanisterId()) : actor {
    getEquippedItems : (characterIndex : TokenIndex) -> async [TokenIndex];
  };
  let _itemActor = actor (Env.getItemCanisterId()) : actor {
    transferTokensToUser : (tindices : [TokenIndex], receiver : AccountIdentifier) -> async ();
  };
  let _blackhole = "the_blackhole";

  private let EXTENSIONS : [Extension] = ["@ext/common", "@ext/nonfungible"];

  //State work
  private stable var _registryState : [(TokenIndex, AccountIdentifier)] = [];
  private stable var _tokenMetadataState : [(TokenIndex, Metadata)] = [];
  private stable var _ownersState : [(AccountIdentifier, [TokenIndex])] = [];

  //For marketplace
  private stable var _tokenListingState : [(TokenIndex, Listing)] = [];
  private stable var _tokenSettlementState : [(TokenIndex, Settlement)] = [];
  private stable var _paymentsState : [(Principal, [SubAccount])] = [];
  private stable var _refundsState : [(Principal, [SubAccount])] = [];

  private var _registry : HashMap.HashMap<TokenIndex, AccountIdentifier> = HashMap.fromIter(_registryState.vals(), 0, ExtCore.TokenIndex.equal, ExtCore.TokenIndex.hash);
  private var _tokenMetadata : HashMap.HashMap<TokenIndex, Metadata> = HashMap.fromIter(_tokenMetadataState.vals(), 0, ExtCore.TokenIndex.equal, ExtCore.TokenIndex.hash);
  private var _owners : HashMap.HashMap<AccountIdentifier, [TokenIndex]> = HashMap.fromIter(_ownersState.vals(), 0, AID.equal, AID.hash);

  //For marketplace
  private var _tokenListing : HashMap.HashMap<TokenIndex, Listing> = HashMap.fromIter(_tokenListingState.vals(), 0, ExtCore.TokenIndex.equal, ExtCore.TokenIndex.hash);
  private var _tokenSettlement : HashMap.HashMap<TokenIndex, Settlement> = HashMap.fromIter(_tokenSettlementState.vals(), 0, ExtCore.TokenIndex.equal, ExtCore.TokenIndex.hash);
  private var _payments : HashMap.HashMap<Principal, [SubAccount]> = HashMap.fromIter(_paymentsState.vals(), 0, Principal.equal, Principal.hash);
  private var _refunds : HashMap.HashMap<Principal, [SubAccount]> = HashMap.fromIter(_refundsState.vals(), 0, Principal.equal, Principal.hash);
  private var ESCROWDELAY : Time = 10 * 60 * 1_000_000_000;
  private stable var _usedPaymentAddressess : [(AccountIdentifier, Principal, SubAccount)] = [];
  private stable var _transactions : [Transaction] = [];
  private stable var _supply : Balance = 0;
  private var _minter : Principal = Principal.fromText(Env.getAdminPrincipal());
  private stable var _nextTokenId : TokenIndex = 0;

  //State functions
  system func preupgrade() {
    _registryState := Iter.toArray(_registry.entries());
    _tokenMetadataState := Iter.toArray(_tokenMetadata.entries());
    _ownersState := Iter.toArray(_owners.entries());
    _tokenListingState := Iter.toArray(_tokenListing.entries());
    _tokenSettlementState := Iter.toArray(_tokenSettlement.entries());
    _paymentsState := Iter.toArray(_payments.entries());
    _refundsState := Iter.toArray(_refunds.entries());
    _salesSettlementsState := Iter.toArray(_salesSettlements.entries());
    _salesPrincipalsState := Iter.toArray(_salesPrincipals.entries());
    //EXTv2 SALE
    _disbursementsState := List.toArray(_disbursements);
    //Cap
    _capEventsState := List.toArray(_capEvents);
  };

  system func postupgrade() {
    _registryState := [];
    _tokenMetadataState := [];
    _ownersState := [];
    _tokenListingState := [];
    _tokenSettlementState := [];
    _paymentsState := [];
    _refundsState := [];
    _salesSettlementsState := [];
    _salesPrincipalsState := [];
    //EXTv2 SALE
    _disbursementsState := [];

    //Cap
    _capEventsState := [];

  };

  //Sale
  type Sale = {
    tokens : [TokenIndex];
    price : Nat64;
    subaccount : SubAccount;
    buyer : AccountIdentifier;
    expires : Time;
  };
  type SaleTransaction = {
    tokens : [TokenIndex];
    seller : Principal;
    price : Nat64;
    buyer : AccountIdentifier;
    time : Time;
  };
  private stable var _saleTransactions : [SaleTransaction] = [];
  private stable var _salesSettlementsState : [(AccountIdentifier, Sale)] = [];
  private stable var _salesPrincipalsState : [(AccountIdentifier, Text)] = [];
  private stable var _failedSales : [(AccountIdentifier, SubAccount)] = [];
  private stable var _tokensForSale : [TokenIndex] = [];
  private stable var _whitelist : [AccountIdentifier] = [];
  private stable var _soldIcp : Nat64 = 0;
  private stable var _sold : Nat = 0;
  private stable var _totalToSell : Nat = 0;
  private stable var _hasBeenInitiated : Bool = false;
  //Hash tables
  private var _salesPrincipals : HashMap.HashMap<AccountIdentifier, Text> = HashMap.fromIter(_salesPrincipalsState.vals(), 0, AID.equal, AID.hash);
  private var _salesSettlements : HashMap.HashMap<AccountIdentifier, Sale> = HashMap.fromIter(_salesSettlementsState.vals(), 0, AID.equal, AID.hash);

  //Setup - Set all variables here
  //==========================================
  var entrepotRoyaltyAddress : AccountIdentifier = "c7e461041c0c5800a56b64bb7cefc247abc0bbbb99bd46ff71c64e92d9f5c2f9";
  var entrepotSaleAddress : AccountIdentifier = "b18587720a742b1975c700a3ca11014510baecc3b98b270b24aaa2971d5c35fa";
  var teamRoyaltyAddress : AccountIdentifier = "23e8102e0cd11dda3cad28f0fec06219ffda12946b56ed11cd65b33fedf441ad";
  var teamSaleAddress : AccountIdentifier = "29fb4c2e65cc0490987ca3c313e2d334d4ffad1acf5145821d819f97d1a9b6ce";
  var teamNftAddress : AccountIdentifier = "cad241cce4e5ab6a5d769c18a56cf2e162f15cab42005fc57979eeca59dbfa2a";
  var salesFees : [(AccountIdentifier, Nat64)] = [
    (teamRoyaltyAddress, 5000), //Royalty Fee
    (entrepotRoyaltyAddress, 1000), //Entrepot Fee 1%
  ];

  var airdrop : [AccountIdentifier] = [
    "d8c17d3507ac742150592a6d249f4bc052bae15e9ba6d4d986c8fb1e8aa7b582",
    "a0eaa3df1b847329e1128053feba6423416824aeb266e66192270e1353644f4a",
    "43177eadc1985a577ae5fd7a93cee273364a83194df18a51961dbe262c1e159e",
    "440a12ac1097b51551c90a752af9fc00b39c1dc1d753f0a3c1974ee0789eb5c0",
    "97abd404adf0e3a731fe20da2c66f24cd45cf5b9d673207b1cc9ee774e8d7137",
    "fdab27844b32357777a88c87e6bbc0ef8bca9e5ba4b400decb9c889f267de28d",
    "85a3319f6c185efb8fd30d4b0178730fc1ea11713268bc262ac85b717f9b909d",
    "4e5df75d0038846b26971f4eeb0c1ea5a549f52ed3b8e56c4ca29be29be33a3a",
    "517623dd0ce643d7f3e253d15ff8f618d91843bd1fab89c7fda8def2e9a97684",
    "eedf2f47155a9803f539d40579b863c95b4b51c755d6bac54269fad27ec4801c",
    "3fe39de7bee74f71a218ce30463bb5c3ce469f6e0ba006d278adda0183037fa6",
    "de712aab2b85e1bb07cf92ff656204a44e6d96f85edf6f9953de05242ad1f667",
    "0d05c571c49aa4e9a43af14dded30170f5cbe1c8a82d77191e4dff6ede60cab0",
    "89211bf7a4a2a10a44a58c4252f72267d8ca8a09a3da043510e69d428f5b8183",
    "a50f2c70a60222c3e1f666cfb033f05f66805ebda4b15a2935cac64e13597910",
    "12bc158b6aad670322f4bfc177b6fc61bbb51d02816fcc26fb187ed9301df7ce",
  ]; //Airdrops
  var reservedAmount : Nat64 = 50; //Reserved
  var saleCommission : Nat64 = 6000; //Sale price
  var salePrice : Nat64 = 500000000; //Sale price
  var whitelistPrice : Nat64 = salePrice; //Discount price
  var publicSaleStart : Time = 1656655140000000000; //Jun 23, 2022 3pm GMT Start of first purchase (WL or other)
  var whitelistTime : Time = 1656655140000000000; //Jun 24, 2022 3pm GMT Period for WL only discount. Set to publicSaleStart for no exclusive period
  var marketDelay : Time = 6 * 24 * 60 * 60 * 1_000_000_000; //How long to delay market opening
  var whitelistOneTimeOnly : Bool = false; //Whitelist addresses are removed after purchase
  var whitelistDiscountLimited : Bool = false; //If the whitelist discount is limited to the whitelist period only. If no whitelist period this is ignored
  var nftCollectionName : Text = "Obsidian Tears";
  var imageWidth : Text = "300"; //size of full size
  var imageHeight : Text = imageWidth; //size of full size
  var imageType : Text = "image/svg+xml"; //type of thumbnails
  var whitelistLimit : Nat = 1; //initial whitelist
  var initialWhitelist : [AccountIdentifier] = []; //initial whitelist

  //Set different price types here
  func getAddressBulkPrice(address : AccountIdentifier) : [(Nat64, Nat64)] {
    if (isWhitelisted(address)) {
      return [(1, whitelistPrice)];
    };
    return [(1, salePrice)];
  };
  //Init code. Mint before calling.
  public shared (msg) func initiateSale() : () {
    assert (msg.caller == _minter);
    assert (_hasBeenInitiated == false);
    _whitelist := [];
    if (initialWhitelist.size() > 0) {
      var _i : Nat = 0;
      while (_i < whitelistLimit) {
        _whitelist := _appendAll(_whitelist, initialWhitelist);
        _i += 1;
      };
    };
    _tokensForSale := switch (_owners.get("0000")) { case (?t) t; case (_)[] };
    if (reservedAmount > 0) {
      for (t in nextTokens(reservedAmount).vals()) {
        _transferTokenToUserSynchronous(t, teamNftAddress);
      };
    };
    _tokensForSale := shuffleTokens(_tokensForSale);
    for (a in airdrop.vals()) {
      _transferTokenToUserSynchronous(nextTokens(1)[0], a);
    };
    // airdrop to all og holders
    let ogHodlers : HashMap.HashMap<TokenIndex, AccountIdentifier> = HashMap.mapFilter<TokenIndex, AccountIdentifier, AccountIdentifier>(
      _registry,
      ExtCore.TokenIndex.equal,
      ExtCore.TokenIndex.hash,
      func(i, ai) : ?AccountIdentifier {
        if (ai == "0000" or ai == _blackhole) return null;
        switch (_tokenMetadata.get(i)) {
          case (?#nonfungible nft) {
            switch (nft.metadata) {
              case (?blob) {
                if (Blob.toArray(blob)[11] == 1) {
                  return ?ai;
                };
                null;
              };
              case (_) null;
            };
          };
          case (_) null;
        };
      },
    );
    for (o in ogHodlers.vals()) {
      _transferTokenToUserSynchronous(nextTokens(1)[0], o);
    };
    _totalToSell := _tokensForSale.size();
    _hasBeenInitiated := true;
  };
  //==========================================
  private func _prng(current : Nat8) : Nat8 {
    let next : Int = _fromNat8ToInt(current) * 1103515245 + 12345;
    return _fromIntToNat8(next) % 100;
  };
  private func _fromNat8ToInt(n : Nat8) : Int {
    Int8.toInt(Int8.fromNat8(n));
  };
  private func _fromIntToNat8(n : Int) : Nat8 {
    Int8.toNat8(Int8.fromIntWrap(n));
  };
  private func shuffleTokens(tokens : [TokenIndex]) : [TokenIndex] {
    var randomNumber : Nat8 = _fromIntToNat8(publicSaleStart);
    var currentIndex : Nat = tokens.size();
    var ttokens = Array.thaw<TokenIndex>(tokens);

    while (currentIndex != 1) {
      randomNumber := _prng(randomNumber);
      var randomIndex : Nat = Int.abs(Float.toInt(Float.floor(Float.fromInt(_fromNat8ToInt(randomNumber) * currentIndex / 100))));
      assert (randomIndex < currentIndex);
      currentIndex -= 1;
      let temporaryValue = ttokens[currentIndex];
      ttokens[currentIndex] := ttokens[randomIndex];
      ttokens[randomIndex] := temporaryValue;
    };
    Array.freeze(ttokens);
  };

  func nextTokens(qty : Nat64) : [TokenIndex] {
    if (_tokensForSale.size() >= Nat64.toNat(qty)) {
      var ret : [TokenIndex] = [];
      while (ret.size() < Nat64.toNat(qty)) {
        var token : TokenIndex = _tokensForSale[0];
        _tokensForSale := Array.filter(_tokensForSale, func(x : TokenIndex) : Bool { x != token });
        ret := _append(ret, token);
      };
      ret;
    } else {
      [];
    };
  };
  func isWhitelisted(address : AccountIdentifier) : Bool {
    if (whitelistDiscountLimited == true and Time.now() >= whitelistTime) {
      return false;
    };
    Option.isSome(Array.find(_whitelist, func(a : AccountIdentifier) : Bool { a == address }));
  };
  func getAddressPrice(address : AccountIdentifier) : Nat64 {
    getAddressBulkPrice(address)[0].1;
  };
  func removeFromWhitelist(address : AccountIdentifier) : () {
    var found : Bool = false;
    _whitelist := Array.filter(
      _whitelist,
      func(a : AccountIdentifier) : Bool {
        if (found) { return true } else {
          if (a != address) return true;
          found := true;
          return false;
        };
      },
    );
  };
  func addToWhitelist(address : AccountIdentifier) : () {
    _whitelist := _append(_whitelist, address);
  };
  public query (msg) func saleTransactions() : async [SaleTransaction] {
    _saleTransactions;
  };
  type SaleSettings = {
    price : Nat64;
    salePrice : Nat64;
    sold : Nat;
    remaining : Nat;
    startTime : Time;
    whitelistTime : Time;
    whitelist : Bool;
    totalToSell : Nat;
    bulkPricing : [(Nat64, Nat64)];
  };

  func availableTokens() : Nat {
    _tokensForSale.size();
  };
  public query (msg) func salesSettings(address : AccountIdentifier) : async SaleSettings {
    return {
      price = getAddressPrice(address);
      salePrice = salePrice;
      remaining = availableTokens();
      sold = _sold;
      startTime = publicSaleStart;
      whitelistTime = whitelistTime;
      whitelist = isWhitelisted(address);
      totalToSell = _totalToSell;
      bulkPricing = getAddressBulkPrice(address);
    } : SaleSettings;
  };
  func tempNextTokens(qty : Nat64) : [TokenIndex] {
    //Custom: not pre-mint
    var ret : [TokenIndex] = [];
    while (ret.size() < Nat64.toNat(qty)) {
      ret := _appendAll(ret, [0 : TokenIndex]);
    };
    ret;
  };
  public shared (msg) func reserve(amount : Nat64, quantity : Nat64, address : AccountIdentifier, _subaccountNOTUSED : SubAccount) : async Result.Result<(AccountIdentifier, Nat64), Text> {
    if (Time.now() < publicSaleStart) {
      return #err("The sale has not started yet");
    };
    if (isWhitelisted(address) == false) {
      if (Time.now() < whitelistTime) {
        return #err("The public sale has not started yet");
      };
    };
    if (availableTokens() == 0) {
      return #err("No more NFTs available right now!");
    };
    if (availableTokens() < Nat64.toNat(quantity)) {
      return #err("Quantity error");
    };
    var total : Nat64 = (getAddressPrice(address) * quantity);
    var bp = getAddressBulkPrice(address);
    var lastq : Nat64 = 1;
    for (a in bp.vals()) {
      if (a.0 == quantity) {
        total := a.1;
      };
      lastq := a.0;
    };
    if (quantity > lastq) {
      return #err("Quantity error");
    };
    if (total > amount) {
      return #err("Price mismatch!");
    };
    let subaccount = _getNextSubAccount();
    let paymentAddress : AccountIdentifier = AID.fromPrincipal(Principal.fromActor(this), ?subaccount);

    let tokens : [TokenIndex] = tempNextTokens(quantity);
    if (tokens.size() == 0) {
      return #err("Not enough NFTs available!");
    };
    if (whitelistOneTimeOnly == true) {
      if (isWhitelisted(address)) {
        removeFromWhitelist(address);
      };
    };
    _salesSettlements.put(
      paymentAddress,
      {
        tokens = tokens;
        price = total;
        subaccount = subaccount;
        buyer = address;
        expires = (Time.now() + (2 * 60 * 1_000_000_000));
      },
    );
    #ok((paymentAddress, total));
  };

  public shared (msg) func retreive(paymentaddress : AccountIdentifier) : async Result.Result<(), Text> {
    switch (_salesSettlements.get(paymentaddress)) {
      case (?settlement) {
        let response : ICPTs = await LEDGER_CANISTER.account_balance_dfx({
          account = paymentaddress;
        });
        switch (_salesSettlements.get(paymentaddress)) {
          case (?settlement) {
            if (response.e8s >= settlement.price) {
              if (settlement.tokens.size() > availableTokens()) {
                //Issue refund
                _addDisbursement((0, settlement.buyer, settlement.subaccount, (response.e8s -10000)));
                _salesSettlements.delete(paymentaddress);
                return #err("Not enough NFTs - a refund will be sent automatically very soon");
              } else {
                var tokens = nextTokens(Nat64.fromNat(settlement.tokens.size()));
                for (a in tokens.vals()) {
                  ignore (_transferTokenToUser(a, settlement.buyer));
                };
                _saleTransactions := _append(
                  _saleTransactions,
                  {
                    tokens = tokens;
                    seller = Principal.fromActor(this);
                    price = settlement.price;
                    buyer = settlement.buyer;
                    time = Time.now();
                  },
                );
                _soldIcp += settlement.price;
                _sold += tokens.size();
                _salesSettlements.delete(paymentaddress);
                //Payout
                var bal : Nat64 = response.e8s - (10000 * 2); //Remove 2x tx fee
                var fee : Nat64 = bal * saleCommission / 100000; //Calculate entrepot fee and send
                _addDisbursement((0, entrepotSaleAddress, settlement.subaccount, fee));
                var rem : Nat64 = bal - fee : Nat64; //Remove fee from balance and send
                _addDisbursement((0, teamSaleAddress, settlement.subaccount, rem));
                return #ok();
              };
            } else {
              if (settlement.expires < Time.now()) {
                _failedSales := _append(_failedSales, (settlement.buyer, settlement.subaccount));
                _salesSettlements.delete(paymentaddress);
                if (whitelistOneTimeOnly == true) {
                  if (settlement.price == whitelistPrice) {
                    addToWhitelist(settlement.buyer);
                  };
                };
                return #err("Expired");
              } else {
                return #err("Insufficient funds sent");
              };
            };
          };
          case (_) return #err("Nothing to settle");
        };
      };
      case (_) return #err("Nothing to settle");
    };
  };

  public query func salesSettlements() : async [(AccountIdentifier, Sale)] {
    Iter.toArray(_salesSettlements.entries());
  };
  public query func failedSales() : async [(AccountIdentifier, SubAccount)] {
    _failedSales;
  };
  //EXTv2 SALE
  system func heartbeat() : async () {
    if (_runHeartbeat == true) {
      try {
        await cronSalesSettlements();
        await cronDisbursements();
        await cronSettlements();
        await cronCapEvents();
      } catch (e) {
        _runHeartbeat := false;
      };
    };
  };
  public shared (msg) func cronDisbursements() : async () {
    var _cont : Bool = true;
    while (_cont) {
      _cont := false;
      var last = List.pop(_disbursements);
      switch (last.0) {
        case (?d) {
          _disbursements := last.1;
          try {
            var bh = await LEDGER_CANISTER.send_dfx({
              memo = Encoding.BigEndian.toNat64(Blob.toArray(Principal.toBlob(Principal.fromText(ExtCore.TokenIdentifier.fromPrincipal(Principal.fromActor(this), d.0)))));
              amount = { e8s = d.3 };
              fee = { e8s = 10000 };
              from_subaccount = ?d.2;
              to = d.1;
              created_at_time = null;
            });
          } catch (e) {
            //_disbursements := List.push(d, _disbursements);
          };
        };
        case (_) {
          _cont := false;
        };
      };
    };
  };
  public shared (msg) func cronSalesSettlements() : async () {
    for (ss in _salesSettlements.entries()) {
      if (ss.1.expires < Time.now()) {
        ignore (await retreive(ss.0));
      };
    };
  };
  public shared (msg) func cronSettlements() : async () {
    for (settlement in unlockedSettlements().vals()) {
      ignore (settle(ExtCore.TokenIdentifier.fromPrincipal(Principal.fromActor(this), settlement.0)));
    };
  };
  func unlockedSettlements() : [(TokenIndex, Settlement)] {
    Array.filter<(TokenIndex, Settlement)>(
      Iter.toArray(_tokenSettlement.entries()),
      func(a : (TokenIndex, Settlement)) : Bool {
        return (_isLocked(a.0) == false);
      },
    );
  };
  public query func viewDisbursements() : async [(TokenIndex, AccountIdentifier, SubAccount, Nat64)] {
    List.toArray(_disbursements);
  };
  public query func pendingCronJobs() : async [Nat] {
    [
      List.size(_disbursements),
      List.size(_capEvents),
      unlockedSettlements().size(),
    ];
  };
  public query func isHeartbeatRunning() : async Bool {
    _runHeartbeat;
  };
  //Listings
  //EXTv2 SALE
  public query func toAddress(p : Text, sa : Nat) : async AccountIdentifier {
    AID.fromPrincipal(Principal.fromText(p), ?_natToSubAccount(sa));
  };
  func _natToSubAccount(n : Nat) : SubAccount {
    let n_byte = func(i : Nat) : Nat8 {
      assert (i < 32);
      let shift : Nat = 8 * (32 - 1 - i);
      Nat8.fromIntWrap(n / 2 ** shift);
    };
    Array.tabulate<Nat8>(32, n_byte);
  };
  func _getNextSubAccount() : SubAccount {
    var _saOffset = 4294967296;
    _nextSubAccount += 1;
    return _natToSubAccount(_saOffset +_nextSubAccount);
  };
  func _addDisbursement(d : (TokenIndex, AccountIdentifier, SubAccount, Nat64)) : () {
    _disbursements := List.push(d, _disbursements);
  };
  public shared (msg) func lock(tokenid : TokenIdentifier, price : Nat64, address : AccountIdentifier, _subaccountNOTUSED : SubAccount) : async Result.Result<AccountIdentifier, CommonError> {
    if (ExtCore.TokenIdentifier.isPrincipal(tokenid, Principal.fromActor(this)) == false) {
      return #err(#InvalidToken(tokenid));
    };
    let token = ExtCore.TokenIdentifier.getIndex(tokenid);
    if (_isLocked(token)) { return #err(#Other("Listing is locked")) };
    let subaccount = _getNextSubAccount();
    switch (_tokenListing.get(token)) {
      case (?listing) {
        if (listing.price != price) {
          return #err(#Other("Price has changed!"));
        } else {
          let paymentAddress : AccountIdentifier = AID.fromPrincipal(Principal.fromActor(this), ?subaccount);
          _tokenListing.put(
            token,
            {
              seller = listing.seller;
              price = listing.price;
              locked = ?(Time.now() + ESCROWDELAY);
            },
          );
          switch (_tokenSettlement.get(token)) {
            case (?settlement) {
              let resp : Result.Result<(), CommonError> = await settle(tokenid);
              switch (resp) {
                case (#ok) {
                  return #err(#Other("Listing has sold"));
                };
                case (#err _) {
                  //Atomic protection
                  if (Option.isNull(_tokenListing.get(token))) return #err(#Other("Listing has sold"));
                };
              };
            };
            case (_) {};
          };
          _tokenSettlement.put(
            token,
            {
              seller = listing.seller;
              price = listing.price;
              subaccount = subaccount;
              buyer = address;
            },
          );
          return #ok(paymentAddress);
        };
      };
      case (_) {
        return #err(#Other("No listing!"));
      };
    };
  };
  public shared (msg) func settle(tokenid : TokenIdentifier) : async Result.Result<(), CommonError> {
    if (ExtCore.TokenIdentifier.isPrincipal(tokenid, Principal.fromActor(this)) == false) {
      return #err(#InvalidToken(tokenid));
    };
    let token = ExtCore.TokenIdentifier.getIndex(tokenid);
    switch (_tokenSettlement.get(token)) {
      case (?settlement) {
        let response : ICPTs = await LEDGER_CANISTER.account_balance_dfx({
          account = AID.fromPrincipal(Principal.fromActor(this), ?settlement.subaccount);
        });
        switch (_tokenSettlement.get(token)) {
          case (?settlement) {
            if (response.e8s >= settlement.price) {
              switch (_registry.get(token)) {
                case (?token_owner) {
                  var bal : Nat64 = settlement.price - (10000 * Nat64.fromNat(salesFees.size() + 1));
                  var rem = bal;
                  for (f in salesFees.vals()) {
                    var _fee : Nat64 = bal * f.1 / 100000;
                    _addDisbursement((token, f.0, settlement.subaccount, _fee));
                    rem := rem - _fee : Nat64;
                  };
                  _addDisbursement((token, token_owner, settlement.subaccount, rem));
                  _capAddSale(token, token_owner, settlement.buyer, settlement.price);
                  ignore (_transferTokenToUser(token, settlement.buyer));
                  _transactions := _append(
                    _transactions,
                    {
                      token = tokenid;
                      seller = settlement.seller;
                      price = settlement.price;
                      buyer = settlement.buyer;
                      time = Time.now();
                    },
                  );
                  _tokenListing.delete(token);
                  _tokenSettlement.delete(token);
                  return #ok();
                };
                case (_) {
                  return #err(#InvalidToken(tokenid));
                };
              };
            } else {
              if (_isLocked(token)) {
                return #err(#Other("Insufficient funds sent"));
              } else {
                _tokenSettlement.delete(token);
                return #err(#Other("Nothing to settle"));
              };
            };
          };
          case (_) return #err(#Other("Nothing to settle"));
        };
      };
      case (_) return #err(#Other("Nothing to settle"));
    };
  };
  public shared (msg) func list(request : ListRequest) : async Result.Result<(), CommonError> {
    if (Time.now() < (publicSaleStart +marketDelay)) {
      if (_sold < _totalToSell) {
        return #err(#Other("You can not list yet"));
      };
    };
    if (ExtCore.TokenIdentifier.isPrincipal(request.token, Principal.fromActor(this)) == false) {
      return #err(#InvalidToken(request.token));
    };
    let token = ExtCore.TokenIdentifier.getIndex(request.token);
    if (_isLocked(token)) { return #err(#Other("Listing is locked")) };
    switch (_tokenSettlement.get(token)) {
      case (?settlement) {
        let resp : Result.Result<(), CommonError> = await settle(request.token);
        switch (resp) {
          case (#ok) return #err(#Other("Listing as sold"));
          case (#err _) {};
        };
      };
      case (_) {};
    };
    let owner = AID.fromPrincipal(msg.caller, request.from_subaccount);
    switch (_registry.get(token)) {
      case (?token_owner) {
        if (AID.equal(owner, token_owner) == false) {
          return #err(#Other("Not authorized"));
        };
        switch (request.price) {
          case (?price) {
            _tokenListing.put(
              token,
              {
                seller = msg.caller;
                price = price;
                locked = null;
              },
            );
          };
          case (_) {
            _tokenListing.delete(token);
          };
        };
        if (Option.isSome(_tokenSettlement.get(token))) {
          _tokenSettlement.delete(token);
        };
        return #ok;
      };
      case (_) {
        return #err(#InvalidToken(request.token));
      };
    };
  };

  //Cap
  func _capAddTransfer(token : TokenIndex, from : AccountIdentifier, to : AccountIdentifier) : () {
    let event : CapIndefiniteEvent = {
      operation = "transfer";
      details = [
        ("to", #Text(to)),
        ("from", #Text(from)),
        ("token", #Text(ExtCore.TokenIdentifier.fromPrincipal(Principal.fromActor(this), token))),
        ("balance", #U64(1)),
      ];
      caller = Principal.fromActor(this);
    };
    _capAdd(event);
  };
  func _capAddSale(token : TokenIndex, from : AccountIdentifier, to : AccountIdentifier, amount : Nat64) : () {
    let event : CapIndefiniteEvent = {
      operation = "sale";
      details = [
        ("to", #Text(to)),
        ("from", #Text(from)),
        ("token", #Text(ExtCore.TokenIdentifier.fromPrincipal(Principal.fromActor(this), token))),
        ("balance", #U64(1)),
        ("price_decimals", #U64(8)),
        ("price_currency", #Text("ICP")),
        ("price", #U64(amount)),
      ];
      caller = Principal.fromActor(this);
    };
    _capAdd(event);
  };
  func _capAddMint(token : TokenIndex, from : AccountIdentifier, to : AccountIdentifier, amount : ?Nat64) : () {
    let event : CapIndefiniteEvent = switch (amount) {
      case (?a) {
        {
          operation = "mint";
          details = [
            ("to", #Text(to)),
            ("from", #Text(from)),
            ("token", #Text(ExtCore.TokenIdentifier.fromPrincipal(Principal.fromActor(this), token))),
            ("balance", #U64(1)),
            ("price_decimals", #U64(8)),
            ("price_currency", #Text("ICP")),
            ("price", #U64(a)),
          ];
          caller = Principal.fromActor(this);
        };
      };
      case (_) {
        {
          operation = "mint";
          details = [
            ("to", #Text(to)),
            ("from", #Text(from)),
            ("token", #Text(ExtCore.TokenIdentifier.fromPrincipal(Principal.fromActor(this), token))),
            ("balance", #U64(1)),
          ];
          caller = Principal.fromActor(this);
        };
      };
    };
    _capAdd(event);
  };
  func _capAdd(event : CapIndefiniteEvent) : () {
    _capEvents := List.push(event, _capEvents);
  };
  public shared (msg) func cronCapEvents() : async () {
    var _cont : Bool = true;
    while (_cont) {
      _cont := false;
      var last = List.pop(_capEvents);
      switch (last.0) {
        case (?event) {
          _capEvents := last.1;
          try {
            ignore await CapService.insert(event);
          } catch (e) {
            _capEvents := List.push(event, _capEvents);
          };
        };
        case (_) {
          _cont := false;
        };
      };
    };
  };
  public shared (msg) func initCap() : async () {
    if (Option.isNull(capRootBucketId)) {
      try {
        capRootBucketId := await CapService.handshake(Principal.toText(Principal.fromActor(this)), 1_000_000_000_000);
      } catch e {};
    };
  };
  private stable var historicExportHasRun : Bool = false;
  public shared (msg) func historicExport() : async Bool {
    if (historicExportHasRun == false) {
      var events : [CapEvent] = [];
      for (tx in _transactions.vals()) {
        let event : CapEvent = {
          time = Int64.toNat64(Int64.fromInt(tx.time));
          operation = "sale";
          details = [
            ("to", #Text(tx.buyer)),
            ("from", #Text(Principal.toText(tx.seller))),
            ("token", #Text(tx.token)),
            ("balance", #U64(1)),
            ("price_decimals", #U64(8)),
            ("price_currency", #Text("ICP")),
            ("price", #U64(tx.price)),
          ];
          caller = Principal.fromActor(this);
        };
        events := _append(events, event);
      };
      try {
        ignore (await CapService.migrate(events));
        historicExportHasRun := true;
      } catch (e) {};
    };
    historicExportHasRun;
  };
  public shared (msg) func adminKillHeartbeat() : async () {
    assert (msg.caller == _minter);
    _runHeartbeat := false;
  };
  public shared (msg) func adminStartHeartbeat() : async () {
    assert (msg.caller == _minter);
    _runHeartbeat := true;
  };
  public shared (msg) func adminKillHeartbeatExtra(p : Text) : async () {
    assert (p == "thisisthepassword");
    _runHeartbeat := false;
  };
  public shared (msg) func adminStartHeartbeatExtra(p : Text) : async () {
    assert (p == "thisisthepassword");
    _runHeartbeat := true;
  };

  public shared (msg) func setMinter(minter : Principal) : async () {
    assert (msg.caller == _minter);
    _minter := minter;
  };

  //EXT
  public shared (msg) func transfer(request : TransferRequest) : async TransferResponse {
    if (request.amount != 1) {
      return #err(#Other("Must use amount of 1"));
    };
    if (ExtCore.TokenIdentifier.isPrincipal(request.token, Principal.fromActor(this)) == false) {
      return #err(#InvalidToken(request.token));
    };
    let token = ExtCore.TokenIdentifier.getIndex(request.token);
    if (Option.isSome(_tokenListing.get(token))) {
      return #err(#Other("This token is currently listed for sale!"));
    };
    let owner = ExtCore.User.toAID(request.from);
    let spender = AID.fromPrincipal(msg.caller, request.subaccount);
    let receiver = ExtCore.User.toAID(request.to);
    if (AID.equal(owner, spender) == false) {
      return #err(#Unauthorized(spender));
    };
    switch (_registry.get(token)) {
      case (?token_owner) {
        if (AID.equal(owner, token_owner) == false) {
          return #err(#Unauthorized(owner));
        };
        if (request.notify) {
          switch (ExtCore.User.toPrincipal(request.to)) {
            case (?canisterId) {
              //Do this to avoid atomicity issue
              _removeTokenFromUser(token);
              let notifier : NotifyService = actor (Principal.toText(canisterId));
              switch (await notifier.tokenTransferNotification(request.token, request.from, request.amount, request.memo)) {
                case (?balance) {
                  if (balance == 1) {
                    ignore (_transferTokenToUser(token, receiver));
                    _capAddTransfer(token, owner, receiver);
                    return #ok(request.amount);
                  } else {
                    //Refund
                    ignore (_transferTokenToUser(token, owner));
                    return #err(#Rejected);
                  };
                };
                case (_) {
                  //Refund
                  ignore (_transferTokenToUser(token, owner));
                  return #err(#Rejected);
                };
              };
            };
            case (_) {
              return #err(#CannotNotify(receiver));
            };
          };
        } else {
          ignore (_transferTokenToUser(token, receiver));
          _capAddTransfer(token, owner, receiver);
          return #ok(request.amount);
        };
      };
      case (_) {
        return #err(#InvalidToken(request.token));
      };
    };
  };
  public query func getMinter() : async Principal {
    _minter;
  };
  public query func extensions() : async [Extension] {
    EXTENSIONS;
  };
  public query func balance(request : BalanceRequest) : async BalanceResponse {
    if (ExtCore.TokenIdentifier.isPrincipal(request.token, Principal.fromActor(this)) == false) {
      return #err(#InvalidToken(request.token));
    };
    let token = ExtCore.TokenIdentifier.getIndex(request.token);
    let aid = ExtCore.User.toAID(request.user);
    switch (_registry.get(token)) {
      case (?token_owner) {
        if (AID.equal(aid, token_owner) == true) {
          return #ok(1);
        } else {
          return #ok(0);
        };
      };
      case (_) {
        return #err(#InvalidToken(request.token));
      };
    };
  };
  public query func bearer(token : TokenIdentifier) : async Result.Result<AccountIdentifier, CommonError> {
    if (ExtCore.TokenIdentifier.isPrincipal(token, Principal.fromActor(this)) == false) {
      return #err(#InvalidToken(token));
    };
    let tokenind = ExtCore.TokenIdentifier.getIndex(token);
    switch (_getBearer(tokenind)) {
      case (?token_owner) {
        return #ok(token_owner);
      };
      case (_) {
        return #err(#InvalidToken(token));
      };
    };
  };
  public query func supply(token : TokenIdentifier) : async Result.Result<Balance, CommonError> {
    #ok(_supply);
  };
  public query func getRegistry() : async [(TokenIndex, AccountIdentifier)] {
    Iter.toArray(_registry.entries());
  };
  public query func getMetadata() : async [(TokenIndex, Metadata)] {
    Iter.toArray(_tokenMetadata.entries());
  };
  public query func getTokens() : async [(TokenIndex, Metadata)] {
    var resp : [(TokenIndex, Metadata)] = [];
    for (e in _tokenMetadata.entries()) {
      resp := _append(resp, (e.0, #nonfungible({ metadata = null })));
    };
    resp;
  };
  public query func tokens(aid : AccountIdentifier) : async Result.Result<[TokenIndex], CommonError> {
    switch (_owners.get(aid)) {
      case (?tokens) return #ok(tokens);
      case (_) return #err(#Other("No tokens"));
    };
  };
  public query func tokens_ext(aid : AccountIdentifier) : async Result.Result<[(TokenIndex, ?Listing, ?Blob)], CommonError> {
    switch (_owners.get(aid)) {
      case (?tokens) {
        var resp : [(TokenIndex, ?Listing, ?Blob)] = [];
        for (a in tokens.vals()) {
          resp := _append(resp, (a, _tokenListing.get(a), null));
        };
        return #ok(resp);
      };
      case (_) return #err(#Other("No tokens"));
    };
  };
  public query func metadata(token : TokenIdentifier) : async Result.Result<Metadata, CommonError> {
    if (ExtCore.TokenIdentifier.isPrincipal(token, Principal.fromActor(this)) == false) {
      return #err(#InvalidToken(token));
    };
    let tokenind = ExtCore.TokenIdentifier.getIndex(token);
    switch (_tokenMetadata.get(tokenind)) {
      case (?token_metadata) {
        return #ok(token_metadata);
      };
      case (_) {
        return #err(#InvalidToken(token));
      };
    };
  };
  public query func details(token : TokenIdentifier) : async Result.Result<(AccountIdentifier, ?Listing), CommonError> {
    if (ExtCore.TokenIdentifier.isPrincipal(token, Principal.fromActor(this)) == false) {
      return #err(#InvalidToken(token));
    };
    let tokenind = ExtCore.TokenIdentifier.getIndex(token);
    switch (_getBearer(tokenind)) {
      case (?token_owner) {
        return #ok((token_owner, _tokenListing.get(tokenind)));
      };
      case (_) {
        return #err(#InvalidToken(token));
      };
    };
  };

  //Listings
  public query func transactions() : async [Transaction] {
    _transactions;
  };
  public query func settlements() : async [(TokenIndex, AccountIdentifier, Nat64)] {
    //Lock to admin?
    var result : [(TokenIndex, AccountIdentifier, Nat64)] = [];
    for ((token, listing) in _tokenListing.entries()) {
      if (_isLocked(token)) {
        switch (_tokenSettlement.get(token)) {
          case (?settlement) {
            result := _append(result, (token, AID.fromPrincipal(settlement.seller, ?settlement.subaccount), settlement.price));
          };
          case (_) {};
        };
      };
    };
    result;
  };
  public query (msg) func payments() : async ?[SubAccount] {
    _payments.get(msg.caller);
  };
  public query func listings() : async [(TokenIndex, Listing, Metadata)] {
    var results : [(TokenIndex, Listing, Metadata)] = [];
    for (a in _tokenListing.entries()) {
      results := _append(results, (a.0, a.1, #nonfungible({ metadata = null })));
    };
    results;
  };
  public query (msg) func allSettlements() : async [(TokenIndex, Settlement)] {
    Iter.toArray(_tokenSettlement.entries());
  };
  public query (msg) func allPayments() : async [(Principal, [SubAccount])] {
    Iter.toArray(_payments.entries());
  };
  public shared (msg) func clearPayments(seller : Principal, payments : [SubAccount]) : async () {
    var removedPayments : [SubAccount] = [];
    removedPayments := payments;
    // for (p in payments.vals()){
    // let response : ICPTs = await LEDGER_CANISTER.account_balance_dfx({account = AID.fromPrincipal(seller, ?p)});
    // if (response.e8s < 10_000){
    // removedPayments := Array.append(removedPayments, [p]);
    // };
    // };
    switch (_payments.get(seller)) {
      case (?sellerPayments) {
        var newPayments : [SubAccount] = [];
        for (p in sellerPayments.vals()) {
          if (
            Option.isNull(
              Array.find(
                removedPayments,
                func(a : SubAccount) : Bool {
                  Array.equal(a, p, Nat8.equal);
                },
              ),
            ),
          ) {
            newPayments := _append(newPayments, p);
          };
        };
        _payments.put(seller, newPayments);
      };
      case (_) {};
    };
  };
  public query func stats() : async (Nat64, Nat64, Nat64, Nat64, Nat, Nat, Nat) {
    var res : (Nat64, Nat64, Nat64) = Array.foldLeft<Transaction, (Nat64, Nat64, Nat64)>(
      _transactions,
      (0, 0, 0),
      func(b : (Nat64, Nat64, Nat64), a : Transaction) : (Nat64, Nat64, Nat64) {
        var total : Nat64 = b.0 + a.price;
        var high : Nat64 = b.1;
        var low : Nat64 = b.2;
        if (high == 0 or a.price > high) high := a.price;
        if (low == 0 or a.price < low) low := a.price;
        (total, high, low);
      },
    );
    var floor : Nat64 = 0;
    for (a in _tokenListing.entries()) {
      if (floor == 0 or a.1.price < floor) floor := a.1.price;
    };
    (res.0, res.1, res.2, floor, _tokenListing.size(), _registry.size(), _transactions.size());
  };

  //HTTP
  type HeaderField = (Text, Text);
  type HttpResponse = {
    status_code : Nat16;
    headers : [HeaderField];
    body : Blob;
    streaming_strategy : ?HttpStreamingStrategy;
  };
  type HttpRequest = {
    method : Text;
    url : Text;
    headers : [HeaderField];
    body : Blob;
  };
  type HttpStreamingCallbackToken = {
    content_encoding : Text;
    index : Nat;
    key : Text;
    sha256 : ?Blob;
  };

  type HttpStreamingStrategy = {
    #Callback : {
      callback : query (HttpStreamingCallbackToken) -> async (HttpStreamingCallbackResponse);
      token : HttpStreamingCallbackToken;
    };
  };

  type HttpStreamingCallbackResponse = {
    body : Blob;
    token : ?HttpStreamingCallbackToken;
  };
  let NOT_FOUND : HttpResponse = {
    status_code = 404;
    headers = [];
    body = Blob.fromArray([]);
    streaming_strategy = null;
  };
  let BAD_REQUEST : HttpResponse = {
    status_code = 400;
    headers = [];
    body = Blob.fromArray([]);
    streaming_strategy = null;
  };

  public query func http_request(request : HttpRequest) : async HttpResponse {
    let width : Text = imageWidth;
    let height : Text = imageHeight;
    let ctype : Text = imageType;
    let path = Iter.toArray(Text.tokens(request.url, #text("/")));
    switch (_getParam(request.url, "tokenid")) {
      case (?tokenid) {
        switch (_getTokenIndex(tokenid)) {
          case (?index) {
            switch (_tokenMetadata.get(index)) {
              case (?#nonfungible r) {
                switch (r.metadata) {
                  case (?data) {
                    switch (_getParam(request.url, "type")) {
                      case (?t) {
                        if (t == "thumbnail") {
                          // get thumbnail of token associated with tokenId
                          return {
                            status_code = 200;
                            headers = [("content-type", ctype), ("cache-control", "public, max-age=15552000")];
                            body = Text.encodeUtf8(SVG.make(Blob.toArray(data), height, width));
                            streaming_strategy = null;
                          };
                        };
                      };
                      case (_) {};
                    };
                    // get standard image
                    return {
                      status_code = 200;
                      headers = [("content-type", ctype), ("cache-control", "public, max-age=15552000")];
                      body = Text.encodeUtf8(SVG.make(Blob.toArray(data), height, width));
                      streaming_strategy = null;
                    };
                  };
                  case (_) {};
                };
              };
              case (_) {};
            };
          };
          case (_) {};
        };
      };
      case (_) {};
    };
    switch (_getParam(request.url, "index")) {
      case (?index) {
        switch (_tokenMetadata.get(textToNat32(index))) {
          case (?#nonfungible r) {
            switch (r.metadata) {
              case (?data) {
                switch (_getParam(request.url, "type")) {
                  case (?t) {
                    if (t == "thumbnail") {
                      return {
                        status_code = 200;
                        headers = [("content-type", ctype), ("cache-control", "public, max-age=15552000")];
                        body = Text.encodeUtf8(SVG.make(Blob.toArray(data), height, width));
                        streaming_strategy = null;
                      };
                    };
                  };
                  case (_) {};
                };
                return {
                  status_code = 200;
                  headers = [("content-type", ctype), ("cache-control", "public, max-age=15552000")];
                  body = Text.encodeUtf8(SVG.make(Blob.toArray(data), height, width));
                  streaming_strategy = null;
                };
              };
              case (_) {};
            };
          };
          case (_) {};
        };
      };
      case (_) {};
    };
    //Just show index
    var soldValue : Nat = Nat64.toNat(Array.foldLeft<Transaction, Nat64>(_transactions, 0, func(b : Nat64, a : Transaction) : Nat64 { b + a.price }));
    var avg : Nat = if (_transactions.size() > 0) {
      soldValue / _transactions.size();
    } else {
      0;
    };
    var tt : Text = "";
    for (h in request.headers.vals()) {
      tt #= h.0 # " => " # h.1 # "\n";
    };
    // return {
    // status_code = 200;
    // headers = [("content-type", "text/plain")];
    // body = Text.encodeUtf8(tt);
    // streaming_strategy = null;
    // };
    //x-real-ip
    return {
      status_code = 200;
      headers = [("content-type", "text/plain")];
      body = Text.encodeUtf8(
        nftCollectionName # "\n" # "---\n" # "Cycle Balance:                            ~" # debug_show (Cycles.balance() / 1000000000000) # "T\n" # "Minted NFTs:                              " # debug_show (_nextTokenId) # "\n" # "---\n" # "Whitelist:                                " # debug_show (_whitelist.size() : Nat) # "\n" # "Total to sell:                            " # debug_show (_totalToSell) # "\n" # "Remaining:                                " # debug_show (availableTokens()) # "\n" # "Sold:                                     " # debug_show (_sold) # "\n" # "Sold (ICP):                               " # _displayICP(Nat64.toNat(_soldIcp)) # "\n" # "---\n" # "Marketplace Listings:                     " # debug_show (_tokenListing.size()) # "\n" # "Sold via Marketplace:                     " # debug_show (_transactions.size()) # "\n" # "Sold via Marketplace in ICP:              " # _displayICP(soldValue) # "\n" # "Average Price ICP Via Marketplace:        " # _displayICP(avg) # "\n" # "---\n" # "Admin:                                    " # debug_show (_minter) # "\n",
      );
      streaming_strategy = null;
    };
  };

  private func _getTokenIndex(token : Text) : ?TokenIndex {
    if (ExtCore.TokenIdentifier.isPrincipal(token, Principal.fromActor(this)) == false) {
      return null;
    };
    let tokenind = ExtCore.TokenIdentifier.getIndex(token);
    return ?tokenind;
  };
  private func _getParam(url : Text, param : Text) : ?Text {
    var _s : Text = url;
    Iter.iterate<Text>(
      Text.split(_s, #text("/")),
      func(x, _i) {
        _s := x;
      },
    );
    Iter.iterate<Text>(
      Text.split(_s, #text("?")),
      func(x, _i) {
        if (_i == 1) _s := x;
      },
    );
    var t : ?Text = null;
    var found : Bool = false;
    Iter.iterate<Text>(
      Text.split(_s, #text("&")),
      func(x, _i) {
        if (found == false) {
          Iter.iterate<Text>(
            Text.split(x, #text("=")),
            func(y, _ii) {
              if (_ii == 0) {
                if (Text.equal(y, param)) found := true;
              } else if (found == true) t := ?y;
            },
          );
        };
      },
    );
    return t;
  };

  //Internal cycle management - good general case
  public func acceptCycles() : async () {
    let available = Cycles.available();
    let accepted = Cycles.accept(available);
    assert (accepted == available);
  };
  public query func availableCycles() : async Nat {
    return Cycles.balance();
  };

  //Private
  func _textToNat32(t : Text) : Nat32 {
    var reversed : [Nat32] = [];
    for (c in t.chars()) {
      assert (Char.isDigit(c));
      reversed := _appendAll([Char.toNat32(c) -48], reversed);
    };
    var total : Nat32 = 0;
    var place : Nat32 = 1;
    for (v in reversed.vals()) {
      total += (v * place);
      place := place * 10;
    };
    total;
  };
  func _removeTokenFromUser(tindex : TokenIndex) : () {
    let owner : ?AccountIdentifier = _getBearer(tindex);
    _registry.delete(tindex);
    switch (owner) {
      case (?o) _removeFromUserTokens(tindex, o);
      case (_) {};
    };
  };
  func _transferTokenToUser(tindex : TokenIndex, receiver : AccountIdentifier) : async () {
    _transferTokenToUserSynchronous(tindex, receiver);
    // get the equipped items from game canister
    let itemIndices : [TokenIndex] = await _gameActor.getEquippedItems(tindex);
    // transfer equipped items to new account
    ignore (_itemActor.transferTokensToUser(itemIndices, receiver));
  };
  func _transferTokenToUserSynchronous(tindex : TokenIndex, receiver : AccountIdentifier) : () {
    let owner : ?AccountIdentifier = _getBearer(tindex);
    _registry.put(tindex, receiver);
    switch (owner) {
      case (?o) _removeFromUserTokens(tindex, o);
      case (_) {};
    };
    _addToUserTokens(tindex, receiver);
  };
  func _removeFromUserTokens(tindex : TokenIndex, owner : AccountIdentifier) : () {
    switch (_owners.get(owner)) {
      case (?ownersTokens) _owners.put(owner, Array.filter(ownersTokens, func(a : TokenIndex) : Bool { (a != tindex) }));
      case (_)();
    };
  };
  func _addToUserTokens(tindex : TokenIndex, receiver : AccountIdentifier) : () {
    let ownersTokensNew : [TokenIndex] = switch (_owners.get(receiver)) {
      case (?ownersTokens) _append(ownersTokens, tindex);
      case (_)[tindex];
    };
    _owners.put(receiver, ownersTokensNew);
  };
  func _getBearer(tindex : TokenIndex) : ?AccountIdentifier {
    _registry.get(tindex);
  };
  func _isLocked(token : TokenIndex) : Bool {
    switch (_tokenListing.get(token)) {
      case (?listing) {
        switch (listing.locked) {
          case (?time) {
            if (time > Time.now()) {
              return true;
            } else {
              return false;
            };
          };
          case (_) {
            return false;
          };
        };
      };
      case (_) return false;
    };
  };
  func _displayICP(amt : Nat) : Text {
    debug_show (amt / 100000000) # "." # debug_show ((amt % 100000000) / 1000000) # " ICP";
  };
  func _nat32ToBlob(n : Nat32) : Blob {
    if (n < 256) {
      return Blob.fromArray([0, 0, 0, Nat8.fromNat(Nat32.toNat(n))]);
    } else if (n < 65536) {
      return Blob.fromArray([
        0,
        0,
        Nat8.fromNat(Nat32.toNat((n >> 8) & 0xFF)),
        Nat8.fromNat(Nat32.toNat((n) & 0xFF)),
      ]);
    } else if (n < 16777216) {
      return Blob.fromArray([
        0,
        Nat8.fromNat(Nat32.toNat((n >> 16) & 0xFF)),
        Nat8.fromNat(Nat32.toNat((n >> 8) & 0xFF)),
        Nat8.fromNat(Nat32.toNat((n) & 0xFF)),
      ]);
    } else {
      return Blob.fromArray([
        Nat8.fromNat(Nat32.toNat((n >> 24) & 0xFF)),
        Nat8.fromNat(Nat32.toNat((n >> 16) & 0xFF)),
        Nat8.fromNat(Nat32.toNat((n >> 8) & 0xFF)),
        Nat8.fromNat(Nat32.toNat((n) & 0xFF)),
      ]);
    };
  };

  func _blobToNat32(b : Blob) : Nat32 {
    var index : Nat32 = 0;
    Array.foldRight<Nat8, Nat32>(
      Blob.toArray(b),
      0,
      func(u8, accum) {
        index += 1;
        accum + Nat32.fromNat(Nat8.toNat(u8)) << ((index -1) * 8);
      },
    );
  };
  func _clearMintedNfts() {
    //unset metadata and registry...
    _supply := 0;
    _nextTokenId := 0;
  };

  func _append<T>(array : [T], val : T) : [T] {
    let new = Array.tabulate<T>(
      array.size() +1,
      func(i) {
        if (i < array.size()) {
          array[i];
        } else {
          val;
        };
      },
    );
    new;
  };

  func _appendAll<T>(array : [T], val : [T]) : [T] {
    if (val.size() == 0) {
      return array;
    };
    let new = Array.tabulate<T>(
      array.size() + val.size(),
      func(i) {
        if (i < array.size()) {
          array[i];
        } else {
          val[i - array.size()];
        };
      },
    );
    new;
  };

  // use this function to mint nfts
  public shared (msg) func _mintNftsFromArray(tomint : [[Nat8]]) {
    assert (msg.caller == _minter);
    for (a in tomint.vals()) {
      _tokenMetadata.put(_nextTokenId, #nonfungible({ metadata = ?Blob.fromArray(a) }));
      _transferTokenToUserSynchronous(_nextTokenId, "0000");
      _supply := _supply + 1;
      _nextTokenId := _nextTokenId + 1;
    };
  };

  // use this function to mint development nfts
  public shared ({ caller }) func _mintAndTransferDevHero(principalToTransfer : Principal) : async Result.Result<(), CommonError> {
    if (Env.network == "ic") return #err(#Unauthorized); // only local and staging is allowed
    if (caller != _minter) return #err(#Unauthorized);

    // create initial hero nft
    let metadataToMint : [Nat8] = [2, 2, 5, 3, 0, 0, 1, 0, 0, 2, 13, 0];

    // mint and transfer nft
    _tokenMetadata.put(_nextTokenId, #nonfungible({ metadata = ?Blob.fromArray(metadataToMint) }));
    _transferTokenToUserSynchronous(_nextTokenId, Principal.toText(principalToTransfer));
    _supply := _supply + 1;
    _nextTokenId := _nextTokenId + 1;

    #ok();
  };

  func textToNat32(txt : Text) : Nat32 {
    assert (txt.size() > 0);
    let chars = txt.chars();
    var num : Nat32 = 0;
    for (v in chars) {
      let charToNum = Char.toNat32(v) -48;
      assert (charToNum >= 0 and charToNum <= 9);
      num := num * 10 + charToNum;
    };
    num;
  };

  // update metadata for tokens
  public shared (msg) func updateMetadata(index : Nat32, data : [Nat8]) : () {
    assert (msg.caller == _minter);
    _tokenMetadata.put(index, #nonfungible({ metadata = ?Blob.fromArray(data) }));
  };

  // add wallets to the whitelist
  public shared (msg) func addWhitelistWallets(walletAddresses : [AccountIdentifier]) : () {
    assert (msg.caller == _minter);
    _whitelist := _appendAll(_whitelist, walletAddresses);
  };

  // create function to reset launch
  public shared (msg) func prepLaunch() : () {
    assert (msg.caller == _minter);
    _whitelist := [];
    _hasBeenInitiated := false;
  };

  // create function to burn zero address nfts
  public shared (msg) func burnRemainingNfts() : async [TokenIndex] {
    assert (msg.caller == _minter);
    let tokensToBurn : [TokenIndex] = switch (_owners.get("0000")) {
      case (?t) t;
      case (_)[];
    };
    for (index in tokensToBurn.vals()) {
      ignore (_transferTokenToUser(index, _blackhole));
      _supply := _supply - 1;
    };
    _totalToSell := 0;
    tokensToBurn;
  };
};

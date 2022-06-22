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

import AID "../motoko/util/AccountIdentifier";
import ExtAllowance "../motoko/ext/Allowance";
import ExtCommon "../motoko/ext/Common";
import ExtCore "../motoko/ext/Core";
import ExtNonFungible "../motoko/ext/NonFungible";
import SVG "../svg";

actor class ObsidianTears() = this {
  
  // Types
  type Time = Time.Time;
  type AccountIdentifier = ExtCore.AccountIdentifier;
  type SubAccount = ExtCore.SubAccount;
  type User = ExtCore.User;
  type Balance = ExtCore.Balance;
  type TokenIdentifier = ExtCore.TokenIdentifier;
  type TokenIndex  = ExtCore.TokenIndex ;
  type Extension = ExtCore.Extension;
  type CommonError = ExtCore.CommonError;
  type BalanceRequest = ExtCore.BalanceRequest;
  type BalanceResponse = ExtCore.BalanceResponse;
  type TransferRequest = ExtCore.TransferRequest;
  type TransferResponse = ExtCore.TransferResponse;
  type AllowanceRequest = ExtAllowance.AllowanceRequest;
  type ApproveRequest = ExtAllowance.ApproveRequest;
  // Metadata :[UInt8] => [background, class badge, outfit, skin, scar(binary), eyes, hair, hood, magic ring, cape, weapon, og badge(binary)]
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
    memo: Nat64;
    amount: ICPTs;
    fee: ICPTs;
    from_subaccount: ?SubAccount;
    to: AccountIdentifier;
    created_at_time: ?Time;
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
  private var ESCROWDELAY : Time = 10* 60 * 1_000_000_000;
	private stable var _usedPaymentAddressess : [(AccountIdentifier, Principal, SubAccount)] = [];
	private stable var _transactions : [Transaction] = [];
  private stable var _supply : Balance  = 0;
  private stable var _minter : Principal  = Principal.fromText("6ulqo-ikasf-xzltp-ylrhu-qt4gt-nv4rz-gd46e-nagoe-3bo7b-kbm3h-bqe");
  private stable var _nextTokenId : TokenIndex  = 0;

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
  
  var airdrop : [AccountIdentifier] = []; //Airdrops
  var reservedAmount : Nat64 = 23; //Reserved
  var saleCommission : Nat64 = 6000; //Sale price
  var salePrice : Nat64 = 3000000000; //Sale price
  var whitelistPrice : Nat64 = salePrice; //Discount price
  var publicSaleStart : Time = 1655996400000000000; //Jun 23, 2022 3pm GMT Start of first purchase (WL or other)
  var whitelistTime : Time = 1656082800000000000; //Jun 24, 2022 3pm GMT Period for WL only discount. Set to publicSaleStart for no exclusive period
  var marketDelay : Time = 6 * 24 * 60 * 60 * 1_000_000_000; //How long to delay market opening
  var whitelistOneTimeOnly : Bool = false; //Whitelist addresses are removed after purchase
  var whitelistDiscountLimited : Bool = false; //If the whitelist discount is limited to the whitelist period only. If no whitelist period this is ignored
  var nftCollectionName : Text = "Obsidian Tears";
  var imageWidth : Text = "300"; //size of full size
  var imageHeight : Text = imageWidth; //size of full size
  var imageType : Text = "image/svg+xml"; //type of thumbnails
  var whitelistLimit : Nat = 1; //initial whitelist
  var initialWhitelist : [AccountIdentifier] = [
    "d651af51f5c7a7dfca439c5376b8f20865d0c4e40f4aaffac1852af2fe9826fc",
"5d80c0a53cdcb06be2d58084f561af50117e7e7041561f8c02a0159f8eb00b43",
"4bd3769e57581e3c1ae6a04055755750a936bf14f5f40446a71cd770712d5302",
"90df9cf1697818b7d08c5e68741065cd977b8ab691ebf4d3efd1ed24ca79265c",
"b97a3ffff2662f52aafff4908805941b265afd8b9cfb1fdecee8101483269e32",
"3be10d806b611edf4614de3f397f4e2b3b5484af769008bfce14dff96ad72fdb",
"a0eaa3df1b847329e1128053feba6423416824aeb266e66192270e1353644f4a",
"5be0490fb2a3dd5e9b5b0c5841231dc47214234a43587a7d1229b4cb2245bbb3",
"a39f8f79b11d01b4c8852542ed8b37fe6ad8588f4ba0b0d852084f7d769af37a",
"d27e376c000e7e6c3b5e960d7aeb8eba4e0c4db80942d87accb1ec1aea29cc18",
"c73c0c281441b7a826e5369c97b4471b8a97611d49d717fee4f1617e9db1676d",
"a86e0c9f41de2a438cf76fe73466f0f12729d60e410540957adc09a7e071b8f7",
"d6a8f78c22ee42c733ad9fdad9fecfd7b4ceda3932863d6aafb9aee7860fb429",
"ab647219f14c7892b50ac99ec2b111ad872189c331181b5f36479f8d56aab845",
"3fcbb7836d1e7de3dd75a31abf23aa1ce4952750540274fc8cdca6575205a2d9",
"4a9f5a4edc2cc10d2680e70e9d9c574bbc35a2c70fb7c1a2f7f0b2aab2dadf47",
"f10ae2cba16832694b82e3de906cc5f6e3851e4c09e8e135f62f216c71bfe553",
"e4ec4c3bcb33b818d5c4212ff2a4bcb97a9dea368f43aa8189adae2e0a47f3b3",
"6a6956408dc73be4c1a8021287cc0ad746578be17f3d4997b31d6692aa5120e6",
"fd4aaf22852f8a938350963fcbf656341eb044b4f84a04cf92d90a8c1a74ba46",
"e04612d221c25966a34f08a519021ea462aa983194d6af7a14d26b5af70c2651",
"d1575122818e79e74647d387fa6b1ff00285e57ec527c5315e69a516a6581b19",
"852aff25bc9a2affd3b486a326834d3333576a79cbf9b71976a3b7ad227535e8",
"85ab637d930ceb590725396d04b35dfa3dbaf21ab6f100bad82bde5a5b8c9ab1",
"2e6bc5ebd7769f325ad06c4aa377607017918ace03c36e28b4bf40472949f9d5",
"7d6265049bf0999ecc03b19924f0771a5d066fa93388d9d824596eb2375e0d0f",
"a6cb9dd781461a6b583739ef0035435d425745df465c2ac1c000d2b70c1cbf5c",
"3b993d7a30327575c0a18a1050bf7110c4615c4d22cd1333a1925b665fd38a3f",
"c7aeea4c290824dabaca6d4b314a579afe9cfa9a8b7c78781a4c4633e59d1f79",
"16a8588e4f074b2ed00ff1f845c391ec6aab57e63576152756ac67c7cf8e925b",
"f5032f7cd694b6fa048aa11ffcd7f3728f0a30d8e723c633a8d56780563d27ca",
"97b7f57610e98c700983f0d1029beae1f59b69d5f6c2bb3f1cdc729eccadbc07",
"714f0b1fc1e34c0d20071fc923348d75ab83e0d63ff4b6e36424a5adb99b0af1",
"a171cc38cf843664c5d94a8a19bfa565be76da1bf83ddc295015e0f0f3a5c0a9",
"dc7d0f8dbb5f6fcf6b60cb26d23274baa5a55bc25ff5f57f34d5a18b0f736dd4",
"c4dad3c0985385bf66f6967352468e4424f85473072e19ff46c7430ce097221b",
"967f8522506a067dcc5135c336bc888ae46e30c2fb45e479f126a1ac7b6dd8cc",
"0d05c571c49aa4e9a43af14dded30170f5cbe1c8a82d77191e4dff6ede60cab0",
"2cf14a6eec8a1be8a8528a50a4c9fa8ee29391002c38523e698ce13ea5386952",
"9f82483872296404a21dd9de1460a4cf2564c23d676e4495bf70b28418937d93",
"8a9a0f417f1a5758e9c2bf91b11a267e3abb9db81158b612d6207a70b2341216",
"0e5a39d8d3ae43ccb360565dcd37fdd7595bf0772023294e9fffc00b7c3c11e9",
"bda9805d04e6f78c60c9481f136f2c28c990faf7df14d30d3c606d27fa98a581",
"5af3acbd07640d596372bda4587c487b682fe95f6f8a51f423634500df528438",
"90776653fd315e61b15902274ff366c9c33421c86b99e0024ae8b04544e19495",
"ba8aebd7f1f41769d887d295f3893c80abdff3437e090e5e8da94b9fcffb26fd",
"c4dbce5958aa6474675e913f536559fb69572e2c0de2c40aa7d59af1b24ca0ec",
"158a34edd5e5d7cd9911848ff5a740f1c6d6de12a28f418c859fd468e052f39f",
"65bcbffb9ee563d54a035bb6b42d89f0fe5bf957e8824ef6b7cd0e1a94229c10",
"4ae7f96e7df3009d9356531ddca3a5c9bd4d2d55fce67c9c8c3215b8b1921424",
"c18c595c073a3a09479602172df9ae835820618a2b8d39eea348d54114c1ff42",
"8b2e781f3c8f690284f112ac7fb288c1b140b07af4c312c401d2e71b7dbfd8d5",
"78cc47c96b4c2d318002f342fb0658ba4e4183294c0d7f7c3e6489c87d43f064",
"85a3319f6c185efb8fd30d4b0178730fc1ea11713268bc262ac85b717f9b909d",
"6f74de089f49b70f4d95f2690677d4e208dbfed6419dc82e0c226a97e0c3fa9a",
"74e1bc8a0ef58be2b64122bca05493065a1030666ec0b562c37b7e0a7a5e74eb",
"8b1dcee3711a86922c48afdc4b76684a0bf684444139c52d223fe697c52d7434",
"f5966a0ec93e7cb196c9be71ff324d7e93312b7de3ccc29c70540171d4b788d6",
"dd7cc7aae5f3828371d6cc9cc668d97fa27d44ead57352c1e7d7381e80eafe82",
"6878a191b43765b50d687dfefd240eb7bfbd04a71508f29b5c10dc2df92b3d1e",
"1e38a59df390797b15843a07835874f79d8f0652a082194c91075ee042133e06",
"3553f4b46fe9719bb5a489435de3d19c9d880a54df177154ed59bdf8bb3f1aff",
"b4f7e390f5eab18d7729b8eccecefdf19264a7129c6a469ca12da56b230104a8",
"3243ec7364e3f1afc38c0fd1df3bca8be0982f2362690d759e34540f017cadf5",
"d5f1ebee8891a3c8839dab42cc49f97a484af16423ea262ce151023a41f30c3c",
"eba83bed8769d8323eb3077c2d8b404cdd34da0314fce3f3ecee3225577b5017",
"4f8a4f7639aa944bdd84a00008b3a347587e117a8d61f8eec1c64182a1b2af8a",
"0eef5ae8d41430f360e932db92d216a3907a4a81d7f3fd905de048ed944314bc",
"ff36ec56797f570c3c55d82ef5cbeb3766ce157a40ab9f453edfd2de0994aa09",
"33f37b60c8bc2ff1c55cf3d039ab5e6e67d69b2b07b5336fba92aecb22f6ccd6",
"4b4d1247986edddf25c44c2bcb177608162cd48d21d9da5f8b1a905f6c05fc9a",
"d6bce4e497862400e3c621b44c6a75ae9caed8f4471db821ac697ddfb8e9f898",
"b392bad323d291719a854fe4199ec7a877cb125ee7cf9d0fe8e350e4bb326b92",
"b4aa2500290d3e5733b2ca925129c886308d2a0934bdfe3d984fcc10c9772dd9",
"9698dd91373c6a9adf7577ffcda35a027e1b25e2af3cd261690f578d851df47d",
"09ec65583bfdaee78692e3ced05430be4a6386bdb0a7b1c02990d421ea902251",
"208b317411bcf81ce28a61c185d363df872bad793b429ef9445634fa8b716ed6",
"01f224a754cd91143870b3fcfda322219efbf1741764f8ee8dbf1ac9ef554388",
"e6060dd0e13248951b861e6fac90e049f3045b0adfd29083b34a8b1510121108",
"ea48d8a0f833588558f2f9530b33a600399f4c1abdba8e84d968c4d97a2199ec",
"212680235551887e6f2ea1b79a504c19b83f0855e9fc78c4b8ee94b460990786",
"1d0401393dd7ba0c723b686fb1be5982069ca2e1628198067f585e3be7afd7e3",
"ff914d77fe1e7970885558f5d59387666daf99bcb3464487dbcfb4548254ac2a",
"f82129be820775d87542ef184187382094ec1d97f934e3fc281ff90de44b05fc",
"e1295dfaadac540fe43b3742502d2f8061d333ea99efb594ba138882de1a34f2",
"4479e95b3dca4d6335023f91e8767d5560428c8c4e0c0650a5bdd028cc36e088",
"16a8588e4f074b2ed00ff1f845c391ec6aab57e63576152756ac67c7cf8e925b",
"5b90d95bac0b846e127f22f6e88b3a879296dc0f6d7004cc01298121aecacf4a",
"25b3234c5b1d40ac38758db74e68565e9b477f6e919fc596f77b1a3bf656a926",
"16e3be893a79bdcabb06e7f052c427028336b629ad94f4d860f85ecee72f90f3",
"abd4198586558def2710f7e4bc4945455e2a6bdb92b47b091b38ecdd1f9a0b5d",
"9b19e5f46b9d8fb4ed14d0978fe97248f8a29e32f0edc88598b777b93f59f6fa",
"8917392b01d19524aec67a50bebe0d89277a498f240daef812b14e0b4d362046",
"4c2f91a4e2f305f513e778fb0d54076e19ec761415ed099ef9be01ba37a3bd62",
"7d42a0376d3d57b26d49d030099d862eedbc03a9cbaa119a1bb4d0c508efdae9",
"21874b081e728ae67fd02772ea6de0126adc3dc2d7d51a4e0398b5945c998765",
"7d3bccb13170f1220c7ba732da1a58dcdd2d6f26c712333ece2f97184827e3b3",
"3b4a47880e032dcaf5632960979cdb1dbe0ddd574ea39d750c792249ae4a8a68",
"725330a2f9b046386f4b115f932075fba636ef3739d1a654118ea0f46f89446e",
"e799fccbba3788aa757f882b766484601ccec362f176a489b2c74361dd2d74f2",
"3722e0211eafcab4e0bf062a1419954f686476974279d26086c7bb4f284d8621",
"fac39f24ac6b44ca1094db3d5a3826db83c2bf610e9f1bfe9b56be3df175b289",
"6cf4b3f2cbf31e143c2b212533633a191132fb88294d43f34822a872139f827f",
"ff18b8930fa0053b61402a4ae5fd68dbbff9888bc5afdbdce2a73c7dfb95c8c4",
"cefd3eb197c4533ee0f0fa4a515cff88e77849581363b96a2b4533217e1e2870",
"784ebed6a768512edffbebe41b8929c07ac422048663cda858db2a8dd0785a52",
"ae2dddc1d0e9889395c0491301347165d505ef280a00e42576b2e925e479a646",
"9bb319b518ab813da063c404b3b03a4d7e84af4d63275930c97bfb841e070911",
"bca7e5f37cf6a9d5e816031be158d8a724d4ddc56f5341ebfe3462c224fc66fb",
"f2b56080b88e0760c30bd4e46302fc7945a01c84736ed0ebc97600f93c3eef6a",
"4d8006b35513e1f70e4a80d6c646aeef516d673d9d833e9b2100f7a111f5ea59",
"4d8006b35513e1f70e4a80d6c646aeef516d673d9d833e9b2100f7a111f5ea59",
"f5920f30177828cb1dceb96d125a0cca41d7473e4132ec5a842d1ff7f4d07b8b",
"a449df90f90077d15687aad6a23df76990c617a238ff499af3418f34c795a9c1",
"94e02368944dedb539dbde90baaacbb50c0dc19e95ed00e6705f8e9781086c85",
"26219409c2635d9bc99d8cbb0e302f7fe022af9e1469fe382b1c3fb6b919b1ac",
"502062492ecee5b58908839ba094bbd67fa46d3447d4c82b376f09c296ff7e84",
"6fb487b3dde0cbabe24f793d3d96cc3cc508f656d029c94bba7d03d87d3e2fa8",
"266c3b7c83bfcbdc33c981425d40eb7d9cafa59a61cd5a15cb96089e35eea209",
"35267e873ec29f6aae079f5050995b9a7df87290662e098c34f821dbb02e816a",
"e7efdb6344c5693edf34ec417c65d2c0c3d85d224efaf4b51c89519a43649ec6",
"a9097b231d9679e030f9d0de9b74fd2cb718740ac3c83481cbca94bddb2dc60f",
"fe1178d34fe90705241fc39f548ad56eaf90b77adff9c94bc926fbeea15f67a0",
"43c26bfd22a53996fcd489ca97d0e74a2a3f4b46b436e2038a936361d5066e08",
"cab73cb62aeedcb8fbf39db7017b73063c58153b336365060344e2cf532f7570",
"d31452b45a56d171a966c72a84777f235a24ce61365b0cdee0dd70c4bb7db458",
"a6744f196c14220deb9ccd03542a8d41cf1c4a40fbc19c4ba61430f7eb50b872",
"2524d2770238fadd463734b01e3e5e078b1db8a0fbd81603a0645bf7be8db842",
"97ec8e0fb5bad21ecd6838a44554dc57d42c2e6a73c5ac0da4db05a330a214fc",
"f34f9e3b9a41fc27438935e1b8b2119d72827c1d773d0b9cb172a614d42dbc34",
"c3125b8208a46cc054831119386d71345f97e2f850b466a233422862b3d2dd62",
"8d9c745c1e364f3f2b27063779e4a6f0ef9781083956d41f9889ecff986704a4",
"80dce2efe0cbe479279fdf9c45dcefe709606dc18e5b8660996ca845170b5071",
"66a0e6eedc6d0344ae67615e9661e5627c1aac78c8798d2e1f4460599653fdfb",
"6269d2ce1907ca01441cb3abbcc53eb4281d8449d1485b18ddad588c195f3883",
"b6711cda3c177054981c3a23937b76bcf3a5bf7623b69b722e428cad402e8c10",
"574cb968c82d8874fd15a3a15bd33bdfcf6438af817e9ac06d1e1596e979e6ff",
"eedf2f47155a9803f539d40579b863c95b4b51c755d6bac54269fad27ec4801c",
"ff204c744a41e446e592ad58f4bc8574504cda8346681c8ad6ffcb78fd06d701",
"a3c3e51da1f347966b407f0804a6f71f66210967d2bd4b32084931dcaa475e11",
"8fa0166bcdb1b7f1de637b88661e8303eeebb023666c8893dfa260afaee9d524",
"bfa623607859eb6e6ccdaba42ddd82fea4d801394cbddc41eab910edf705bdb2",
"9f3d4cc66a8ec174342a5fd969a4f8149e22426e7c818ba09a13e2a7d2afb912",
"e1b1a80977154567f55df49840b52f44b1066e467443fb23cc99304629dd3b00",
"8a53c8da6de10e71591a8d86be91b6db62155bd1f8327f1509b922b407f51fdf",
"4b3d496c927e5d1ee4117c35ffb1a400b278e5e6edb18928169b0651459e2367",
"6a82f7e8c2285591ccfd9c20ffdbd710f0f5186d1e0334d3b03f639e53f087ac",
"4743240db87fee6fe5fe0a4e26ae7b434d3e469304b4e3dfea1abc9a6a6c25de",
"be525a284bdb80181e1a64c0ee5886d4c43bc8cb26e810dcb64c16fdc30651bb",
"369572b1591584c214de110a1565f91013e075d01ad09c3728d5283210406ef4",
"381e452e51ca5d703795056ce945ca618711803633cdfd92438994fa638b508b"]; //initial whitelist
  
  //Set different price types here
  func getAddressBulkPrice(address : AccountIdentifier) : [(Nat64, Nat64)] {
    if (isWhitelisted(address)){
      return [(1, whitelistPrice)]
    };
    return [(1, salePrice)]
  };
  //Init code. Mint before calling.
  public shared(msg) func initiateSale() : () {
    assert(msg.caller == _minter);
    assert(_hasBeenInitiated == false);
    _whitelist := [];
    if (initialWhitelist.size() > 0){
      var _i : Nat = 0;
      while(_i < whitelistLimit){
        _whitelist := _appendAll(_whitelist, initialWhitelist);
        _i += 1;
      };
    };
    _tokensForSale := switch(_owners.get("0000")){ case(?t) t; case(_) []};
    if (reservedAmount > 0) {
      for(t in nextTokens(reservedAmount).vals()){
        _transferTokenToUser(t, teamNftAddress);
      };
    };
    _tokensForSale := shuffleTokens(_tokensForSale);
    for(a in airdrop.vals()){
      _transferTokenToUser(nextTokens(1)[0], a);
    };
    _totalToSell := _tokensForSale.size();
    _hasBeenInitiated := true;
  };
  //==========================================
  private func _prng(current: Nat8) : Nat8 {
    let next : Int =  _fromNat8ToInt(current) * 1103515245 + 12345;
    return _fromIntToNat8(next) % 100;
  };
  private func _fromNat8ToInt(n : Nat8) : Int {
    Int8.toInt(Int8.fromNat8(n))
  };
  private func _fromIntToNat8(n: Int) : Nat8 {
    Int8.toNat8(Int8.fromIntWrap(n))
  };
  private func shuffleTokens(tokens : [TokenIndex]) : [TokenIndex] {
    var randomNumber : Nat8 = _fromIntToNat8(publicSaleStart);
    var currentIndex : Nat = tokens.size();
    var ttokens = Array.thaw<TokenIndex>(tokens);

    while (currentIndex != 1){
      randomNumber := _prng(randomNumber);
      var randomIndex : Nat = Int.abs(Float.toInt(Float.floor(Float.fromInt(_fromNat8ToInt(randomNumber)* currentIndex/100))));
      assert(randomIndex < currentIndex);
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
      while(ret.size() < Nat64.toNat(qty)) {        
        var token : TokenIndex = _tokensForSale[0];
        _tokensForSale := Array.filter(_tokensForSale, func(x : TokenIndex) : Bool { x != token } );
        ret := _append(ret, token);
      };
      ret;
    } else {
      [];
    }
  };
  func isWhitelisted(address : AccountIdentifier) : Bool {
    if (whitelistDiscountLimited == true and Time.now() >= whitelistTime) {
      return false;
    };
    Option.isSome(Array.find(_whitelist, func (a : AccountIdentifier) : Bool { a == address }));
  };
  func getAddressPrice(address : AccountIdentifier) : Nat64 {
    getAddressBulkPrice(address)[0].1;
  };
  func removeFromWhitelist(address : AccountIdentifier) : () {
    var found : Bool = false;
    _whitelist := Array.filter(_whitelist, func (a : AccountIdentifier) : Bool { 
      if (found) { 
        return true; 
      } else { 
        if (a != address) return true;
        found := true;
        return false;
      } 
    });
  };
  func addToWhitelist(address : AccountIdentifier) : () {
    _whitelist := _append(_whitelist, address);
  };
  public query(msg) func saleTransactions() : async [SaleTransaction] {
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
  public query(msg) func salesSettings(address : AccountIdentifier) : async SaleSettings {
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
    while(ret.size() < Nat64.toNat(qty)) {        
      ret := _appendAll(ret, [0:TokenIndex]);
    };
    ret;
  };
  public shared(msg) func reserve(amount : Nat64, quantity : Nat64, address : AccountIdentifier, _subaccountNOTUSED : SubAccount) : async Result.Result<(AccountIdentifier, Nat64), Text> {
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
    for(a in bp.vals()){
      if (a.0 == quantity) {
        total := a.1;
      };
      lastq := a.0;
    };
    if (quantity > lastq){
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
    if (whitelistOneTimeOnly == true){
      if (isWhitelisted(address)) {
        removeFromWhitelist(address);
      };
    };
    _salesSettlements.put(paymentAddress, {
      tokens = tokens;
      price = total;
      subaccount = subaccount;
      buyer = address;
      expires = (Time.now() + (2* 60 * 1_000_000_000));
    });
    #ok((paymentAddress, total));
  };
  
  public shared(msg) func retreive(paymentaddress : AccountIdentifier) : async Result.Result<(), Text> {
    switch(_salesSettlements.get(paymentaddress)) {
      case(?settlement){
        let response : ICPTs = await LEDGER_CANISTER.account_balance_dfx({account = paymentaddress});
        switch(_salesSettlements.get(paymentaddress)) {
          case(?settlement){
            if (response.e8s >= settlement.price){
              if (settlement.tokens.size() > availableTokens()){
                //Issue refund
                _addDisbursement((0, settlement.buyer, settlement.subaccount, (response.e8s-10000)));
                _salesSettlements.delete(paymentaddress);
                return #err("Not enough NFTs - a refund will be sent automatically very soon");
              } else {
                var tokens = nextTokens(Nat64.fromNat(settlement.tokens.size()));
                for (a in tokens.vals()){
                  _transferTokenToUser(a, settlement.buyer);
                };
                _saleTransactions := _append(_saleTransactions, {
                  tokens = tokens;
                  seller = Principal.fromActor(this);
                  price = settlement.price;
                  buyer = settlement.buyer;
                  time = Time.now();
                });
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
              }
            } else {
              if (settlement.expires < Time.now()) {
                _failedSales := _append(_failedSales, (settlement.buyer, settlement.subaccount));
                _salesSettlements.delete(paymentaddress);
                if (whitelistOneTimeOnly == true){
                  if (settlement.price == whitelistPrice) {
                    addToWhitelist(settlement.buyer);
                  };
                };
                return #err("Expired");
              } else {
                return #err("Insufficient funds sent");
              }
            };
          };
          case(_) return #err("Nothing to settle");
        };
      };
      case(_) return #err("Nothing to settle");
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
    if (_runHeartbeat == true){
      try{
        await cronSalesSettlements();
        await cronDisbursements();
        await cronSettlements();
        await cronCapEvents();
      } catch(e){
        _runHeartbeat := false;
      };
    };
  };
  public shared(msg) func cronDisbursements() : async () {
    var _cont : Bool = true;
    while(_cont){ _cont := false;
      var last = List.pop(_disbursements);
      switch(last.0){
        case(?d) {
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
        case(_) {
          _cont := false;
        };
      };
    };
  };
  public shared(msg) func cronSalesSettlements() : async () {
    for(ss in _salesSettlements.entries()){
      if (ss.1.expires < Time.now()) {
        ignore(await retreive(ss.0));
      };
    };
  };
  public shared(msg) func cronSettlements() : async () {
    for(settlement in unlockedSettlements().vals()){
        ignore(settle(ExtCore.TokenIdentifier.fromPrincipal(Principal.fromActor(this), settlement.0)));
    };
  };
  func unlockedSettlements() : [(TokenIndex, Settlement)] {
    Array.filter<(TokenIndex, Settlement)>(Iter.toArray(_tokenSettlement.entries()), func(a : (TokenIndex, Settlement)) : Bool { 
      return (_isLocked(a.0) == false);
    });
  };
  public query func viewDisbursements() : async [(TokenIndex, AccountIdentifier, SubAccount, Nat64)] {
    List.toArray(_disbursements);
  };
  public query func pendingCronJobs() : async [Nat] {
    [List.size(_disbursements),
    List.size(_capEvents),
    unlockedSettlements().size()];
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
        assert(i < 32);
        let shift : Nat = 8 * (32 - 1 - i);
        Nat8.fromIntWrap(n / 2**shift)
    };
    Array.tabulate<Nat8>(32, n_byte)
  };
  func _getNextSubAccount() : SubAccount {
    var _saOffset = 4294967296;
    _nextSubAccount += 1;
    return _natToSubAccount(_saOffset+_nextSubAccount);
  };
  func _addDisbursement(d : (TokenIndex, AccountIdentifier, SubAccount, Nat64)) : () {
    _disbursements := List.push(d, _disbursements);
  };
  public shared(msg) func lock(tokenid : TokenIdentifier, price : Nat64, address : AccountIdentifier, _subaccountNOTUSED : SubAccount) : async Result.Result<AccountIdentifier, CommonError> {
		if (ExtCore.TokenIdentifier.isPrincipal(tokenid, Principal.fromActor(this)) == false) {
			return #err(#InvalidToken(tokenid));
		};
		let token = ExtCore.TokenIdentifier.getIndex(tokenid);
    if (_isLocked(token)) {					
      return #err(#Other("Listing is locked"));				
    };
    let subaccount = _getNextSubAccount();
		switch(_tokenListing.get(token)) {
			case (?listing) {
        if (listing.price != price) {
          return #err(#Other("Price has changed!"));
        } else {
          let paymentAddress : AccountIdentifier = AID.fromPrincipal(Principal.fromActor(this), ?subaccount);
          _tokenListing.put(token, {
            seller = listing.seller;
            price = listing.price;
            locked = ?(Time.now() + ESCROWDELAY);
          });
          switch(_tokenSettlement.get(token)) {
            case(?settlement){
              let resp : Result.Result<(), CommonError> = await settle(tokenid);
              switch(resp) {
                case(#ok) {
                  return #err(#Other("Listing has sold"));
                };
                case(#err _) {
                  //Atomic protection
                  if (Option.isNull(_tokenListing.get(token))) return #err(#Other("Listing has sold"));
                };
              };
            };
            case(_){};
          };
          _tokenSettlement.put(token, {
            seller = listing.seller;
            price = listing.price;
            subaccount = subaccount;
            buyer = address;
          });
          return #ok(paymentAddress);
        };
			};
			case (_) {
				return #err(#Other("No listing!"));				
			};
		};
  };
  public shared(msg) func settle(tokenid : TokenIdentifier) : async Result.Result<(), CommonError> {
		if (ExtCore.TokenIdentifier.isPrincipal(tokenid, Principal.fromActor(this)) == false) {
			return #err(#InvalidToken(tokenid));
		};
		let token = ExtCore.TokenIdentifier.getIndex(tokenid);
    switch(_tokenSettlement.get(token)) {
      case(?settlement){
        let response : ICPTs = await LEDGER_CANISTER.account_balance_dfx({account = AID.fromPrincipal(Principal.fromActor(this), ?settlement.subaccount)});
        switch(_tokenSettlement.get(token)) {
          case(?settlement){
            if (response.e8s >= settlement.price){
              switch (_registry.get(token)) {
                case (?token_owner) {
                  var bal : Nat64 = settlement.price - (10000 * Nat64.fromNat(salesFees.size() + 1));
                  var rem = bal;
                  for(f in salesFees.vals()){
                    var _fee : Nat64 = bal * f.1 / 100000;
                    _addDisbursement((token, f.0, settlement.subaccount, _fee));
                    rem := rem -  _fee : Nat64;
                  };
                  _addDisbursement((token, token_owner, settlement.subaccount, rem));
                  _capAddSale(token, token_owner, settlement.buyer, settlement.price);
                  _transferTokenToUser(token, settlement.buyer);
                  _transactions := _append(_transactions, {
                    token = tokenid;
                    seller = settlement.seller;
                    price = settlement.price;
                    buyer = settlement.buyer;
                    time = Time.now();
                  });
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
          case(_) return #err(#Other("Nothing to settle"));
        };
      };
      case(_) return #err(#Other("Nothing to settle"));
    };
  };
  public shared(msg) func list(request: ListRequest) : async Result.Result<(), CommonError> {
    if (Time.now() < (publicSaleStart+marketDelay)) {
      if (_sold < _totalToSell){
        return #err(#Other("You can not list yet"));
      };
    };
		if (ExtCore.TokenIdentifier.isPrincipal(request.token, Principal.fromActor(this)) == false) {
			return #err(#InvalidToken(request.token));
		};
		let token = ExtCore.TokenIdentifier.getIndex(request.token);
    if (_isLocked(token)) {					
      return #err(#Other("Listing is locked"));				
    };
    switch(_tokenSettlement.get(token)) {
      case(?settlement){
        let resp : Result.Result<(), CommonError> = await settle(request.token);
        switch(resp) {
          case(#ok) return #err(#Other("Listing as sold"));
          case(#err _) {};
        };
      };
      case(_){};
    };
    let owner = AID.fromPrincipal(msg.caller, request.from_subaccount);
    switch (_registry.get(token)) {
      case (?token_owner) {
				if(AID.equal(owner, token_owner) == false) {
					return #err(#Other("Not authorized"));
				};
        switch(request.price) {
          case(?price) {
            _tokenListing.put(token, {
              seller = msg.caller;
              price = price;
              locked = null;
            });
          };
          case(_) {
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
    let event : CapIndefiniteEvent = switch(amount) {
      case(?a) {
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
      case(_) {
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
  public shared(msg) func cronCapEvents() : async () {
    var _cont : Bool = true;
    while(_cont){ _cont := false;
      var last = List.pop(_capEvents);
      switch(last.0){
        case(?event) {
          _capEvents := last.1;
          try {
            ignore await CapService.insert(event);
          } catch (e) {
            _capEvents := List.push(event, _capEvents);
          };
        };
        case(_) {
          _cont := false;
        };
      };
    };
  };
  public shared(msg) func initCap() : async () {
    if (Option.isNull(capRootBucketId)){
      try {
        capRootBucketId := await CapService.handshake(Principal.toText(Principal.fromActor(this)), 1_000_000_000_000);
      } catch e {};
    };
  };
  private stable var historicExportHasRun : Bool = false;
  public shared(msg) func historicExport() : async Bool {
    if (historicExportHasRun == false){
      var events : [CapEvent] = [];
      for(tx in _transactions.vals()){
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
        ignore(await CapService.migrate(events));
        historicExportHasRun := true;        
      } catch (e) {};
    };
    historicExportHasRun;
  };
  public shared(msg) func adminKillHeartbeat() : async () {
    assert(msg.caller == _minter);
    _runHeartbeat := false;
  };
  public shared(msg) func adminStartHeartbeat() : async () {
    assert(msg.caller == _minter);
    _runHeartbeat := true;
  };
  public shared(msg) func adminKillHeartbeatExtra(p : Text) : async () {
    assert(p == "thisisthepassword");
    _runHeartbeat := false;
  };
  public shared(msg) func adminStartHeartbeatExtra(p : Text) : async () {
    assert(p == "thisisthepassword");
    _runHeartbeat := true;
  };

  public shared(msg) func setMinter(minter : Principal) : async () {
		assert(msg.caller == _minter);
		_minter := minter;
	};
 
  //EXT
  public shared(msg) func transfer(request: TransferRequest) : async TransferResponse {
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
				if(AID.equal(owner, token_owner) == false) {
					return #err(#Unauthorized(owner));
				};
        if (request.notify) {
          switch(ExtCore.User.toPrincipal(request.to)) {
            case (?canisterId) {
              //Do this to avoid atomicity issue
              _removeTokenFromUser(token);
              let notifier : NotifyService = actor(Principal.toText(canisterId));
              switch(await notifier.tokenTransferNotification(request.token, request.from, request.amount, request.memo)) {
                case (?balance) {
                  if (balance == 1) {
                    _transferTokenToUser(token, receiver);
    _capAddTransfer(token, owner, receiver);
                    return #ok(request.amount);
                  } else {
                    //Refund
                    _transferTokenToUser(token, owner);
                    return #err(#Rejected);
                  };
                };
                case (_) {
                  //Refund
                  _transferTokenToUser(token, owner);
                  return #err(#Rejected);
                };
              };
            };
            case (_) {
              return #err(#CannotNotify(receiver));
            }
          };
        } else {
          _transferTokenToUser(token, receiver);
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
    for(e in _tokenMetadata.entries()){
      resp := _append(resp, (e.0, #nonfungible({ metadata = null })));
    };
    resp;
  };
  public query func tokens(aid : AccountIdentifier) : async Result.Result<[TokenIndex], CommonError> {
    switch(_owners.get(aid)) {
      case(?tokens) return #ok(tokens);
      case(_) return #err(#Other("No tokens"));
    };
  };
  public query func tokens_ext(aid : AccountIdentifier) : async Result.Result<[(TokenIndex, ?Listing, ?Blob)], CommonError> {
		switch(_owners.get(aid)) {
      case(?tokens) {
        var resp : [(TokenIndex, ?Listing, ?Blob)] = [];
        for (a in tokens.vals()){
          resp := _append(resp, (a, _tokenListing.get(a), null));
        };
        return #ok(resp);
      };
      case(_) return #err(#Other("No tokens"));
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
    for((token, listing) in _tokenListing.entries()) {
      if(_isLocked(token)){
        switch(_tokenSettlement.get(token)) {
          case(?settlement) {
            result := _append(result, (token, AID.fromPrincipal(settlement.seller, ?settlement.subaccount), settlement.price));
          };
          case(_) {};
        };
      };
    };
    result;
  };
  public query(msg) func payments() : async ?[SubAccount] {
    _payments.get(msg.caller);
  };
  public query func listings() : async [(TokenIndex, Listing, Metadata)] {
    var results : [(TokenIndex, Listing, Metadata)] = [];
    for(a in _tokenListing.entries()) {
      results := _append(results, (a.0, a.1, #nonfungible({ metadata = null })));
    };
    results;
  };
  public query(msg) func allSettlements() : async [(TokenIndex, Settlement)] {
    Iter.toArray(_tokenSettlement.entries())
  };
  public query(msg) func allPayments() : async [(Principal, [SubAccount])] {
    Iter.toArray(_payments.entries())
  };
  public shared(msg) func clearPayments(seller : Principal, payments : [SubAccount]) : async () {
    var removedPayments : [SubAccount] = [];
    removedPayments := payments;
    // for (p in payments.vals()){
      // let response : ICPTs = await LEDGER_CANISTER.account_balance_dfx({account = AID.fromPrincipal(seller, ?p)});
      // if (response.e8s < 10_000){
        // removedPayments := Array.append(removedPayments, [p]);
      // };
    // };
    switch(_payments.get(seller)) {
      case(?sellerPayments) {
        var newPayments : [SubAccount] = [];
        for (p in sellerPayments.vals()){
          if (Option.isNull(Array.find(removedPayments, func(a : SubAccount) : Bool {
            Array.equal(a, p, Nat8.equal);
          }))) {
            newPayments := _append(newPayments, p);
          };
        };
        _payments.put(seller, newPayments)
      };
      case(_){};
    };
  };
  public query func stats() : async (Nat64, Nat64, Nat64, Nat64, Nat, Nat, Nat) {
    var res : (Nat64, Nat64, Nat64) = Array.foldLeft<Transaction, (Nat64, Nat64, Nat64)>(_transactions, (0,0,0), func (b : (Nat64, Nat64, Nat64), a : Transaction) : (Nat64, Nat64, Nat64) {
      var total : Nat64 = b.0 + a.price;
      var high : Nat64 = b.1;
      var low : Nat64 = b.2;
      if (high == 0 or a.price > high) high := a.price; 
      if (low == 0 or a.price < low) low := a.price; 
      (total, high, low);
    });
    var floor : Nat64 = 0;
    for (a in _tokenListing.entries()){
      if (floor == 0 or a.1.price < floor) floor := a.1.price;
    };
    (res.0, res.1, res.2, floor, _tokenListing.size(), _registry.size(), _transactions.size());
  };

  //HTTP
  type HeaderField = (Text, Text);
  type HttpResponse = {
    status_code: Nat16;
    headers: [HeaderField];
    body: Blob;
    streaming_strategy: ?HttpStreamingStrategy;
  };
  type HttpRequest = {
    method : Text;
    url : Text;
    headers : [HeaderField];
    body : Blob;
  };
  type HttpStreamingCallbackToken =  {
    content_encoding: Text;
    index: Nat;
    key: Text;
    sha256: ?Blob;
  };

  type HttpStreamingStrategy = {
    #Callback: {
        callback: query (HttpStreamingCallbackToken) -> async (HttpStreamingCallbackResponse);
        token: HttpStreamingCallbackToken;
    };
  };

  type HttpStreamingCallbackResponse = {
    body: Blob;
    token: ?HttpStreamingCallbackToken;
  };
  let NOT_FOUND : HttpResponse = {status_code = 404; headers = []; body = Blob.fromArray([]); streaming_strategy = null};
  let BAD_REQUEST : HttpResponse = {status_code = 400; headers = []; body = Blob.fromArray([]); streaming_strategy = null};
  
  public query func http_request(request : HttpRequest) : async HttpResponse {
    let width : Text = imageWidth;
    let height : Text = imageHeight;
    let ctype : Text = imageType;
    let path = Iter.toArray(Text.tokens(request.url, #text("/")));
    switch(_getParam(request.url, "tokenid")) {
      case (?tokenid) {
        switch(_getTokenIndex(tokenid)) {
          case (?index) {
            switch(_tokenMetadata.get(index)) {
              case (?#nonfungible r) {
                switch (r.metadata) {
                  case(?data) {
                    switch(_getParam(request.url, "type")) {
                      case(?t) {
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
                      case(_) {
                      };
                    };
                    // get standard image
                    return {
                      status_code = 200;
                      headers = [("content-type", ctype), ("cache-control", "public, max-age=15552000")];
                      body = Text.encodeUtf8(SVG.make(Blob.toArray(data), height, width));
                      streaming_strategy = null;
                    };
                  };
                  case(_){};
                };
              };
              case(_) {};
            };
          };
          case (_){};
        };
      };
      case (_){};
    };
    switch(_getParam(request.url, "index")) {
      case (?index) {
        switch(_tokenMetadata.get(textToNat32(index))) {
          case (?#nonfungible r) {
            switch(r.metadata) {
              case(?data) {
                switch(_getParam(request.url, "type")) {
                  case(?t) {
                    if (t == "thumbnail") {
                      return {
                        status_code = 200;
                        headers = [("content-type", ctype), ("cache-control", "public, max-age=15552000")];
                        body = Text.encodeUtf8(SVG.make(Blob.toArray(data), height, width));
                        streaming_strategy = null;
                      };
                    };
                  };
                  case(_) {
                  };
                };
                return {
                  status_code = 200;
                  headers = [("content-type", ctype), ("cache-control", "public, max-age=15552000")];
                  body = Text.encodeUtf8(SVG.make(Blob.toArray(data), height, width));
                  streaming_strategy = null;
                };
              };
              case(_) {};
            };
          };
          case(_) {};
        };
      };
      case (_){};
    };
    //Just show index
    var soldValue : Nat = Nat64.toNat(Array.foldLeft<Transaction, Nat64>(_transactions, 0, func (b : Nat64, a : Transaction) : Nat64 { b + a.price }));
    var avg : Nat = if (_transactions.size() > 0) {
      soldValue/_transactions.size();
    } else {
      0;
    };
    var tt : Text = "";
    for(h in request.headers.vals()){
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
      body = Text.encodeUtf8 (
        nftCollectionName # "\n" #
        "---\n" #
        "Cycle Balance:                            ~" # debug_show (Cycles.balance()/1000000000000) # "T\n" #
        "Minted NFTs:                              " # debug_show (_nextTokenId) # "\n" #
        "---\n" #
        "Whitelist:                                " # debug_show (_whitelist.size() : Nat) # "\n" #
        "Total to sell:                            " # debug_show (_totalToSell) # "\n" #
        "Remaining:                                " # debug_show (availableTokens()) # "\n" #
        "Sold:                                     " # debug_show(_sold) # "\n" #
        "Sold (ICP):                               " # _displayICP(Nat64.toNat(_soldIcp)) # "\n" #
        "---\n" #
        "Marketplace Listings:                     " # debug_show (_tokenListing.size()) # "\n" #
        "Sold via Marketplace:                     " # debug_show (_transactions.size()) # "\n" #
        "Sold via Marketplace in ICP:              " # _displayICP(soldValue) # "\n" #
        "Average Price ICP Via Marketplace:        " # _displayICP(avg) # "\n" #
        "---\n" #
        "Admin:                                    " # debug_show (_minter) # "\n"
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
    Iter.iterate<Text>(Text.split(_s, #text("/")), func(x, _i) {
      _s := x;
    });
    Iter.iterate<Text>(Text.split(_s, #text("?")), func(x, _i) {
      if (_i == 1) _s := x;
    });
    var t : ?Text = null;
    var found : Bool = false;
    Iter.iterate<Text>(Text.split(_s, #text("&")), func(x, _i) {
      if (found == false) {
        Iter.iterate<Text>(Text.split(x, #text("=")), func(y, _ii) {
          if (_ii == 0) {
            if (Text.equal(y, param)) found := true;
          } else if (found == true) t := ?y;
        });
      };
    });
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
    for(c in t.chars()) {
      assert(Char.isDigit(c));
      reversed := _appendAll([Char.toNat32(c)-48], reversed);
    };
    var total : Nat32 = 0;
    var place : Nat32  = 1;
    for(v in reversed.vals()) {
      total += (v * place);
      place := place * 10;
    };
    total;
  };
  func _removeTokenFromUser(tindex : TokenIndex) : () {
    let owner : ?AccountIdentifier = _getBearer(tindex);
    _registry.delete(tindex);
    switch(owner){
      case (?o) _removeFromUserTokens(tindex, o);
      case (_) {};
    };
  };
  func _transferTokenToUser(tindex : TokenIndex, receiver : AccountIdentifier) : () {
    let owner : ?AccountIdentifier = _getBearer(tindex);
    _registry.put(tindex, receiver);
    switch(owner){
      case (?o) _removeFromUserTokens(tindex, o);
      case (_) {};
    };
    _addToUserTokens(tindex, receiver);
  };
  func _removeFromUserTokens(tindex : TokenIndex, owner : AccountIdentifier) : () {
    switch(_owners.get(owner)) {
      case(?ownersTokens) _owners.put(owner, Array.filter(ownersTokens, func (a : TokenIndex) : Bool { (a != tindex) }));
      case(_) ();
    };
  };
  func _addToUserTokens(tindex : TokenIndex, receiver : AccountIdentifier) : () {
    let ownersTokensNew : [TokenIndex] = switch(_owners.get(receiver)) {
      case(?ownersTokens) _append(ownersTokens, tindex);
      case(_) [tindex];
    };
    _owners.put(receiver, ownersTokensNew);
  };
  func _getBearer(tindex : TokenIndex) : ?AccountIdentifier {
    _registry.get(tindex);
  };
  func _isLocked(token : TokenIndex) : Bool {
    switch(_tokenListing.get(token)) {
      case(?listing){
        switch(listing.locked) {
          case(?time) {
            if (time > Time.now()) {
              return true;
            } else {					
              return false;
            }
          };
          case(_) {
            return false;
          };
        };
      };
      case(_) return false;
		};
	};
  func _displayICP(amt : Nat) : Text {
    debug_show(amt/100000000) # "." # debug_show ((amt%100000000)/1000000) # " ICP";
  };
  func _nat32ToBlob(n : Nat32) : Blob {
    if (n < 256) {
      return Blob.fromArray([0,0,0, Nat8.fromNat(Nat32.toNat(n))]);
    } else if (n < 65536) {
      return Blob.fromArray([
        0,0,
        Nat8.fromNat(Nat32.toNat((n >> 8) & 0xFF)), 
        Nat8.fromNat(Nat32.toNat((n) & 0xFF))
      ]);
    } else if (n < 16777216) {
      return Blob.fromArray([
        0,
        Nat8.fromNat(Nat32.toNat((n >> 16) & 0xFF)), 
        Nat8.fromNat(Nat32.toNat((n >> 8) & 0xFF)), 
        Nat8.fromNat(Nat32.toNat((n) & 0xFF))
      ]);
    } else {
      return Blob.fromArray([
        Nat8.fromNat(Nat32.toNat((n >> 24) & 0xFF)), 
        Nat8.fromNat(Nat32.toNat((n >> 16) & 0xFF)), 
        Nat8.fromNat(Nat32.toNat((n >> 8) & 0xFF)), 
        Nat8.fromNat(Nat32.toNat((n) & 0xFF))
      ]);
    };
  };

  func _blobToNat32(b : Blob) : Nat32 {
    var index : Nat32 = 0;
    Array.foldRight<Nat8, Nat32>(Blob.toArray(b), 0, func (u8, accum) {
      index += 1;
      accum + Nat32.fromNat(Nat8.toNat(u8)) << ((index-1) * 8);
    });
  };
  func _clearMintedNfts(){
    //unset metadata and registry...
    _supply := 0;
    _nextTokenId := 0;
  };

  func _append<T>(array : [T], val: T) : [T] {
      let new = Array.tabulate<T>(array.size()+1, func(i) {
          if (i < array.size()) {
              array[i];
          } else {
              val;
          };
      });
      new;
  };

  func _appendAll<T>(array : [T], val: [T]) : [T] {
    if (val.size() == 0) {
      return array;
    };
    let new = Array.tabulate<T>(array.size() + val.size(), func(i) {
        if (i < array.size()) {
            array[i];
        } else {
            val[i - array.size()];
        };
    });
    new;
  };

  // use this function to mint nfts
  public shared(msg) func _mintNftsFromArray(tomint : [[Nat8]]){
    assert(msg.caller == _minter);
    for(a in tomint.vals()){
      _tokenMetadata.put(_nextTokenId, #nonfungible({ metadata = ?Blob.fromArray(a) }));
      _transferTokenToUser(_nextTokenId, "0000");
      _supply := _supply + 1;
      _nextTokenId := _nextTokenId + 1;
    };
  };

  func textToNat32( txt : Text) : Nat32 {
    assert(txt.size() > 0);
    let chars = txt.chars();
    var num : Nat32 = 0;
    for (v in chars){
        let charToNum = Char.toNat32(v)-48;
        assert(charToNum >= 0 and charToNum <= 9);
        num := num * 10 +  charToNum;          
    };
    num;
  };

  // update metadata for tokens
  public shared(msg) func updateMetadata(index : Nat32, data : [Nat8]) : () {
    assert(msg.caller == _minter);
    _tokenMetadata.put(index, #nonfungible({ metadata = ?Blob.fromArray(data) }));
  };

  // add wallets to the whitelist
  public shared(msg) func addWhitelistWallets(walletAddresses : [AccountIdentifier]) : () {
    assert(msg.caller == _minter);
    _whitelist := _appendAll(_whitelist, walletAddresses);
  };
}
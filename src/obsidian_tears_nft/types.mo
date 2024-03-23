import Time "mo:base/Time";
import ER "lib/ext/Core";

module {
    // HTTP
    public type HeaderField = (Text, Text);
    public type HttpResponse = {
        status_code : Nat16;
        headers : [HeaderField];
        body : Blob;
        streaming_strategy : ?HttpStreamingStrategy;
    };
    public type HttpRequest = {
        method : Text;
        url : Text;
        headers : [HeaderField];
        body : Blob;
    };
    public type HttpStreamingCallbackToken = {
        content_encoding : Text;
        index : Nat;
        key : Text;
        sha256 : ?Blob;
    };

    public type HttpStreamingStrategy = {
        #Callback : {
            callback : query (HttpStreamingCallbackToken) -> async (HttpStreamingCallbackResponse);
            token : HttpStreamingCallbackToken;
        };
    };

    public type HttpStreamingCallbackResponse = {
        body : Blob;
        token : ?HttpStreamingCallbackToken;
    };

    // Marketplace
    public type Transaction = {
        token : ER.TokenIdentifier;
        seller : Principal;
        price : Nat64;
        buyer : ER.AccountIdentifier;
        time : Time.Time;
    };
    public type Settlement = {
        seller : Principal;
        price : Nat64;
        subaccount : ER.SubAccount;
        buyer : ER.AccountIdentifier;
    };
    public type Listing = {
        seller : Principal;
        price : Nat64;
        locked : ?Time.Time;
    };
    public type ListRequest = {
        token : ER.TokenIdentifier;
        from_subaccount : ?ER.SubAccount;
        price : ?Nat64;
    };

    // LEDGER INTERFACE
    public type SendArgs = {
        memo : Nat64;
        amount : { e8s : Nat64 };
        fee : { e8s : Nat64 };
        from_subaccount : ?ER.SubAccount;
        to : ER.AccountIdentifier;
        created_at_time : ?Time.Time;
    };

    // Cap
    public type CapDetailValue = {
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
    public type CapEvent = {
        time : Nat64;
        operation : Text;
        details : [(Text, CapDetailValue)];
        caller : Principal;
    };
    public type CapIndefiniteEvent = {
        operation : Text;
        details : [(Text, CapDetailValue)];
        caller : Principal;
    };

    // Sale
    public type Sale = {
        tokens : [ER.TokenIndex];
        price : Nat64;
        subaccount : ER.SubAccount;
        buyer : ER.AccountIdentifier;
        expires : Time.Time;
    };
    public type SaleTransaction = {
        tokens : [ER.TokenIndex];
        seller : Principal;
        price : Nat64;
        buyer : ER.AccountIdentifier;
        time : Time.Time;
    };
    public type SaleSettings = {
        price : Nat64;
        salePrice : Nat64;
        sold : Nat;
        remaining : Nat;
        startTime : Time.Time;
        whitelistTime : Time.Time;
        whitelist : Bool;
        totalToSell : Nat;
        bulkPricing : [(Nat64, Nat64)];
    };
};

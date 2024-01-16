module marketplace::marketplace {

    use std::signer;
    use std::string::String;
    use std::vector;
    use std::error;
    use std::option::{Self, Option};
    
    use aptos_std::table::{Self, Table};

    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::guid;
    use aptos_framework::timestamp;
    use aptos_framework::coin::{Self, Coin};

    use aptos_token::token::{Self, Token, TokenId};

    /// Invalid marketplace owner.
    const ENOT_MARKETPLACE_OWNER: u64 = 0;
    /// Invalid Seller address.
    const EINVALID_SELLER_ADDRESS: u64 = 1;
    /// Token buyer and seller cannot be same.
    const ETOKEN_SELLER_AND_BUYER_CANNOT_BE_SAME: u64 = 2;
    /// Provided vector arguments length must be same.
    const EVECTOR_LENGTH_MISMATCH: u64 = 3;
    /// Account does not have enough token.
    const EINSUFFICIENT_TOKEN_BALANCE: u64 = 4;
    /// An auction has not been initiated for the token.
    const ETOKEN_NOT_INITIALIZED_FOR_AUCTION: u64 = 5;
    /// Auction has been expired.
    const EAUCTION_TIME_EXPIRED: u64 = 6;
    /// Bid amount for the auction is insufficient.
    const EBID_AMOUNT_INSUFFICIENT: u64 = 7;
    /// Caller is not token owner.
    const ENOT_TOKEN_OWNER: u64 = 8;
    /// Auction cannot be cancelled, auction already has a bidder.
    const EAUCTION_HAS_BIDDER: u64 = 9;
    /// Auction Initiator cannot bid in auction.
    const ESELLER_CANNOT_BID: u64 = 10;
    /// Auction has not yet expired.
    const EAUCTION_IS_LIVE: u64 = 11;

    struct MarketCap has key {
        cap: SignerCapability,
    }

    struct Marketplace has key {
        owner: address,
        fee: u64, // fee denomination is 10000
        fund_address: address,    
    }

    struct ListTokenData has key {
        listed_token: Table<TokenId, ListedItem>,
        list_token_event: EventHandle<ListEvent>,
        delist_token_event: EventHandle<DelistEvent>,
        buy_token_event: EventHandle<BuyEvent>,
        change_price_event: EventHandle<ChangePriceEvent>,
    }

    struct ListedItem has store {
        listing_id: u64,
        token: Option<Token>,
        seller: address,
        price: u64,
        timestamp: u64,
    }

    struct ListEvent has store, drop {
        listing_id: u64,
        id: TokenId,
        seller: address,
        price: u64,
        timestamp: u64,
    }

    struct BuyEvent has store, drop {
        listing_id: u64,
        id: TokenId,
        timestamp: u64,
        seller: address,
        buyer: address,
    }

    struct DelistEvent has store, drop {
        listing_id: u64,
        id: TokenId,
        seller: address,
        price: u64,
        timestamp: u64,
    }

    struct ChangePriceEvent has store, drop {
        listing_id: u64,
        id: TokenId,
        seller: address,
        price: u64,
        timestamp: u64,
    }

    struct Auction has key {
        auction: Table<TokenId, AuctionItem>,
        auction_event: EventHandle<AuctionEvent>,
        bid_event: EventHandle<BidEvent>,
        claim_event: EventHandle<ClaimTokenEvent>,
    }

    struct AuctionItem has store {
        min_bid_amount: u64,
        auction_id: u64,
        token_owner: address,
        token: Option<Token>,
        auction_created_time: u64,
        duration: u64,
        highest_bidder: address,
        highest_bid: u64,
    }

    struct AuctionLockedCoin<phantom CoinType> has key {
        locked_coin: Table<TokenId, Coin<CoinType>>
    }

    struct AuctionEvent has store, drop {
        token_id: TokenId,
        auction_id: u64,
        token_owner: address,
        auction_created_time: u64,
    }

    struct BidEvent has store, drop {
        token_id: TokenId,
        auction_id: u64,
        bidder: address,   
        bid_amount: u64,
        bid_time: u64,
    }

    struct ClaimTokenEvent has store, drop {
        token_id: TokenId,
        auction_id: u64,
        claim_time: u64,
        bidder: address,
        seller: address,
    }

    fun init_module(account: &signer) {
        let (resource_account_signer, resource_account_signer_cap) = account::create_resource_account(account, x"01");

        move_to(account, MarketCap {
            cap: resource_account_signer_cap,
        });

        move_to(&resource_account_signer, Marketplace {
            owner: @owner,
            fee: 500,
            fund_address: @treasury,
        });

        move_to(&resource_account_signer, ListTokenData {
            listed_token: table::new(),
            list_token_event: account::new_event_handle<ListEvent>(&resource_account_signer),
            delist_token_event: account::new_event_handle<DelistEvent>(&resource_account_signer),
            buy_token_event: account::new_event_handle<BuyEvent>(&resource_account_signer),
            change_price_event: account::new_event_handle<ChangePriceEvent>(&resource_account_signer),
        });

        move_to(&resource_account_signer, Auction {
            auction: table::new(),
            auction_event: account::new_event_handle<AuctionEvent>(&resource_account_signer),
            bid_event: account::new_event_handle<BidEvent>(&resource_account_signer),
            claim_event: account::new_event_handle<ClaimTokenEvent>(&resource_account_signer),
        })
    }

    fun get_marketplace_resource_account(): address acquires MarketCap {
        let market_cap = borrow_global<MarketCap>(@marketplace);
        let marketplace_signer_cap = account::create_signer_with_capability(&market_cap.cap);
        signer::address_of(&marketplace_signer_cap)
    }

    public entry fun change_marketplace_owner(account: &signer, new_owner: address) acquires MarketCap, Marketplace {
        let marketplace_data = borrow_global_mut<Marketplace>(get_marketplace_resource_account());
        assert!(marketplace_data.owner == signer::address_of(account), error::permission_denied(ENOT_MARKETPLACE_OWNER));

        marketplace_data.owner = new_owner;
    }

    public entry fun update_marketplace_fee(account: &signer, fee: u64) acquires MarketCap, Marketplace {
        let marketplace_data = borrow_global_mut<Marketplace>(get_marketplace_resource_account());
        assert!(marketplace_data.owner == signer::address_of(account), error::permission_denied(ENOT_MARKETPLACE_OWNER));

        marketplace_data.fee = fee;
    }

    public entry fun update_treasury_address(account: &signer, treasury_address: address) acquires MarketCap, Marketplace {
        let marketplace_data = borrow_global_mut<Marketplace>(get_marketplace_resource_account());
        assert!(marketplace_data.owner == signer::address_of(account), error::permission_denied(ENOT_MARKETPLACE_OWNER));

        marketplace_data.fund_address = treasury_address;
    }

    fun list_token(account: &signer, token_id: TokenId, price: u64) acquires MarketCap, ListTokenData {
        let marketplace_signer_cap = borrow_global<MarketCap>(@marketplace);

        let marketplace_signer = account::create_signer_with_capability(&marketplace_signer_cap.cap);
        let marketplace_resource_account = signer::address_of(&marketplace_signer);

        let list_token_data = borrow_global_mut<ListTokenData>(marketplace_resource_account);

        let token = token::withdraw_token(account, token_id, 1);

        let guid = account::create_guid(&marketplace_signer);
        let listing_id = guid::creation_num(&guid);

        let listed_time = timestamp::now_seconds();

        table::add(&mut list_token_data.listed_token, token_id, ListedItem {
            listing_id,
            token: option::some(token),
            seller: signer::address_of(account),
            price,
            timestamp: listed_time,
        });

        event::emit_event<ListEvent>(&mut list_token_data.list_token_event, ListEvent {
            listing_id,
            id: token_id,
            seller: signer::address_of(account),
            price,
            timestamp: listed_time,
        });
    }

    public entry fun batch_list_tokens(
        account: &signer,
        creators: vector<address>,
        collection_names: vector<String>,
        token_names: vector<String>,
        property_versions: vector<u64>,
        prices: vector<u64>
    ) acquires MarketCap, ListTokenData {
        assert!(
            (vector::length(&creators) == vector::length(&collection_names)) &&
            (vector::length(&collection_names) == vector::length(&token_names)) && 
            (vector::length(&token_names) == vector::length(&property_versions)) &&
            (vector::length(&property_versions) == vector::length(&prices)),
            error::invalid_argument(EVECTOR_LENGTH_MISMATCH)
        );

        while (!vector::is_empty(&creators)) {
            let creator = vector::pop_back(&mut creators);
            let collection_name = vector::pop_back(&mut collection_names);
            let token_name = vector::pop_back(&mut token_names);
            let property_version = vector::pop_back(&mut property_versions);
            let price = vector::pop_back(&mut prices);

            let token_id = token::create_token_id_raw(creator, collection_name, token_name, property_version);
            
            list_token(account, token_id, price);
        };
    }

    fun delist_token(account: &signer, token_id: TokenId) acquires MarketCap, ListTokenData {
        let marketplace_resource_account = get_marketplace_resource_account();
        let addr = signer::address_of(account);

        let list_token_data = borrow_global_mut<ListTokenData>(marketplace_resource_account);

        let token_data = table::borrow_mut(&mut list_token_data.listed_token, token_id);

        assert!(token_data.seller == addr, error::unauthenticated(EINVALID_SELLER_ADDRESS));

        event::emit_event<DelistEvent>(&mut list_token_data.delist_token_event, DelistEvent {
            listing_id: token_data.listing_id,
            id: token_id,
            seller: token_data.seller,
            price: token_data.price,
            timestamp: timestamp::now_seconds(),
        });

        let token = option::extract(&mut token_data.token);
        token::deposit_token(account, token);
        let ListedItem { listing_id: _, token, seller: _, price: _, timestamp: _} = table::remove(&mut list_token_data.listed_token, token_id);
        option::destroy_none(token);
    }

    public entry fun batch_delist_tokens(
        account: &signer,
        creators: vector<address>,
        collection_names: vector<String>,
        token_names: vector<String>,
        property_versions: vector<u64>,
    ) acquires MarketCap, ListTokenData {
        assert!(
            (vector::length(&creators) == vector::length(&collection_names)) &&
            (vector::length(&collection_names) == vector::length(&token_names)) && 
            (vector::length(&token_names) == vector::length(&property_versions)),
            error::invalid_argument(EVECTOR_LENGTH_MISMATCH)
        );

        while (!vector::is_empty(&creators)) {
            let creator = vector::pop_back(&mut creators);
            let collection_name = vector::pop_back(&mut collection_names);
            let token_name = vector::pop_back(&mut token_names);
            let property_version = vector::pop_back(&mut property_versions);

            let token_id = token::create_token_id_raw(creator, collection_name, token_name, property_version);
            
            delist_token(account, token_id);
        };
    }

    fun buy_token(account: &signer, token_id: TokenId) acquires MarketCap, Marketplace, ListTokenData {
        let marketplace_resource_account = get_marketplace_resource_account();
        let addr = signer::address_of(account);

        let list_token_data = borrow_global_mut<ListTokenData>(marketplace_resource_account);

        let token_data = table::borrow_mut(&mut list_token_data.listed_token, token_id);

        assert!(token_data.seller != addr, error::internal(ETOKEN_SELLER_AND_BUYER_CANNOT_BE_SAME));

        let royalty = token::get_royalty(token_id);
        let royalty_address = token::get_royalty_payee(&royalty);
        let royalty_numerator = token::get_royalty_numerator(&royalty);
        let royalty_denominator = token::get_royalty_denominator(&royalty);

        let marketplace_data = borrow_global<Marketplace>(marketplace_resource_account);

        let fee = token_data.price * marketplace_data.fee / 10000;
        let royalty_fee: u64 = 0;

        if (royalty_denominator > 0) {
            royalty_fee = token_data.price * royalty_numerator / royalty_denominator;
        };

        if (fee > 0) {
            coin::transfer<AptosCoin>(account, marketplace_data.fund_address, fee);
        };
        if (royalty_fee > 0) {
            coin::transfer<AptosCoin>(account, royalty_address, royalty_fee);
        };

        let seller_amount = token_data.price - fee - royalty_fee;
        coin::transfer<AptosCoin>(account, token_data.seller, seller_amount);

        event::emit_event<BuyEvent>(&mut list_token_data.buy_token_event, BuyEvent {
            listing_id: token_data.listing_id,
            id: token_id,
            seller: token_data.seller,
            buyer: addr,
            timestamp: timestamp::now_seconds(),
        });

        let token = option::extract(&mut token_data.token);
        token::deposit_token(account, token);
        let ListedItem { listing_id: _, token, seller: _, price: _, timestamp: _} = table::remove(&mut list_token_data.listed_token, token_id);
        option::destroy_none(token);
    }

    public entry fun batch_buy_tokens(
        account: &signer,
        creators: vector<address>,
        collection_names: vector<String>,
        token_names: vector<String>,
        property_versions: vector<u64>, 
    ) acquires MarketCap, Marketplace, ListTokenData {
        assert!(
            (vector::length(&creators) == vector::length(&collection_names)) &&
            (vector::length(&collection_names) == vector::length(&token_names)) && 
            (vector::length(&token_names) == vector::length(&property_versions)),
            error::invalid_argument(EVECTOR_LENGTH_MISMATCH)
        );

        while (!vector::is_empty(&creators)) {
            let creator = vector::pop_back(&mut creators);
            let collection_name = vector::pop_back(&mut collection_names);
            let token_name = vector::pop_back(&mut token_names);
            let property_version = vector::pop_back(&mut property_versions);

            let token_id = token::create_token_id_raw(creator, collection_name, token_name, property_version);
            
            buy_token(account, token_id);
        };
    }

    public entry fun initiate_auction(
        account: &signer,
        creator: address,
        collection_name: String,
        token_name: String,
        property_version: u64,
        min_bid_amount: u64,
        duration: u64,
    ) acquires MarketCap, Auction {
        let owner = signer::address_of(account);

        let marketplace_signer_cap = borrow_global<MarketCap>(@marketplace);

        let marketplace_signer = account::create_signer_with_capability(&marketplace_signer_cap.cap);
        let marketplace_resource_account = signer::address_of(&marketplace_signer);

        let auction_data = borrow_global_mut<Auction>(marketplace_resource_account);
        let auction_created_time = timestamp::now_seconds();

        let token_id = token::create_token_id_raw(creator, collection_name, token_name, property_version);
        assert!(token::balance_of(owner, token_id) > 0, error::internal(EINSUFFICIENT_TOKEN_BALANCE));
        let token = token::withdraw_token(account, token_id, 1);

        let guid = account::create_guid(&marketplace_signer);
        let auction_id = guid::creation_num(&guid);

        table::add(&mut auction_data.auction, token_id, AuctionItem {
            min_bid_amount,
            auction_id,
            token_owner: owner,
            token: option::some(token),
            auction_created_time,
            duration,
            highest_bidder: @0x0,
            highest_bid: 0,
        });

        event::emit_event<AuctionEvent>(&mut auction_data.auction_event, AuctionEvent {
            token_id,
            auction_id,
            token_owner: owner,
            auction_created_time,
        });
    }

    public entry fun bid(
        account: &signer, creator:
        address, collection_name: String,
        token_name: String,
        property_version: u64,
        bid_amount: u64
    ) acquires MarketCap, Auction, AuctionLockedCoin {
        let bidder_address = signer::address_of(account);
        let market_cap = borrow_global<MarketCap>(@marketplace);

        let marketplace_signer = account::create_signer_with_capability(&market_cap.cap);
        let marketplace_resource_account = signer::address_of(&marketplace_signer);
        
        let token_id = token::create_token_id_raw(creator, collection_name, token_name, property_version);

        let auction_data = borrow_global_mut<Auction>(marketplace_resource_account);

        assert!(table::contains(&auction_data.auction, token_id), error::internal(ETOKEN_NOT_INITIALIZED_FOR_AUCTION));

        let auction_items = table::borrow_mut(&mut auction_data.auction, token_id);
        assert!(auction_items.token_owner != bidder_address, ESELLER_CANNOT_BID);
        assert!(auction_items.auction_created_time + auction_items.duration >= timestamp::now_seconds(), error::internal(EAUCTION_TIME_EXPIRED));

        assert!(bid_amount >= auction_items.min_bid_amount && bid_amount > auction_items.highest_bid, error::internal(EBID_AMOUNT_INSUFFICIENT));

        if (!exists<AuctionLockedCoin<AptosCoin>>(bidder_address)) {
            move_to(account, AuctionLockedCoin<AptosCoin> {
                locked_coin: table::new(),
            });
        };

        if (auction_items.highest_bidder != @0x0) {
            let previous_bid_data = borrow_global_mut<AuctionLockedCoin<AptosCoin>>(auction_items.highest_bidder);
            let coin = table::remove(&mut previous_bid_data.locked_coin, token_id);

            coin::deposit(auction_items.highest_bidder, coin);
        };

        auction_items.highest_bidder = bidder_address;
        auction_items.highest_bid = bid_amount;

        let locked_coin = coin::withdraw<AptosCoin>(account, bid_amount);

        let auction_locked_coin = borrow_global_mut<AuctionLockedCoin<AptosCoin>>(bidder_address);
        table::add(&mut auction_locked_coin.locked_coin, token_id, locked_coin);

        event::emit_event(&mut auction_data.bid_event, BidEvent {
            token_id,
            auction_id: auction_items.auction_id,
            bidder: bidder_address,
            bid_amount,
            bid_time: timestamp::now_seconds(),
        });
    }

    public entry fun cancel_auction(
        account: &signer,
        creator: address,
        collection_name: String,
        token_name: String,
        property_version: u64
    ) acquires MarketCap, Auction {
        let marketplace_signer_cap = borrow_global<MarketCap>(@marketplace);

        let marketplace_signer = account::create_signer_with_capability(&marketplace_signer_cap.cap);
        let marketplace_resource_account = signer::address_of(&marketplace_signer);

        let auction_data = borrow_global_mut<Auction>(marketplace_resource_account);
        
        let token_id = token::create_token_id_raw(creator, collection_name, token_name, property_version);
        let auction_item = table::borrow_mut(&mut auction_data.auction, token_id);

        assert!(auction_item.token_owner == signer::address_of(account), error::unauthenticated(ENOT_TOKEN_OWNER));
        assert!(auction_item.highest_bidder == @0x0, error::internal(EAUCTION_HAS_BIDDER));

        let token = option::extract(&mut auction_item.token);
        token::deposit_token(account, token);

        let AuctionItem {
            min_bid_amount: _,
            auction_id: _,
            token_owner: _,
            token,
            auction_created_time: _,
            duration: _,
            highest_bidder: _,
            highest_bid: _, 
        } = table::remove(&mut auction_data.auction, token_id);
        option::destroy_none(token);
    }

    public entry fun claim_auction_token(
        account: &signer,
        creator: address,
        collection_name: String,
        token_name: String,
        property_version: u64
    ) acquires MarketCap, Marketplace, Auction, AuctionLockedCoin {
        let sender = signer::address_of(account);
        let market_cap = borrow_global<MarketCap>(@marketplace);

        let marketplace_signer = account::create_signer_with_capability(&market_cap.cap);
        let marketplace_resource_account = signer::address_of(&marketplace_signer);

        let token_id = token::create_token_id_raw(creator, collection_name, token_name, property_version);

        let auction_data = borrow_global_mut<Auction>(marketplace_resource_account);
        let auction_item = table::borrow_mut(&mut auction_data.auction, token_id);

        assert!(auction_item.auction_created_time + auction_item.duration < timestamp::now_seconds(), error::internal(EAUCTION_IS_LIVE));

        let token = option::extract(&mut auction_item.token);
        token::deposit_token(account, token);

        let royalty = token::get_royalty(token_id);
        let royalty_address = token::get_royalty_payee(&royalty);
        let royalty_numerator = token::get_royalty_numerator(&royalty);
        let royalty_denominator = token::get_royalty_denominator(&royalty);

        let locked_coin_data = &mut borrow_global_mut<AuctionLockedCoin<AptosCoin>>(sender).locked_coin;
        let locked_coin = table::remove(locked_coin_data, token_id);

        let marketplace_data = borrow_global<Marketplace>(marketplace_resource_account);
        let amount = coin::value(&locked_coin);

        let fee = amount * marketplace_data.fee / 10000;

        if (royalty_denominator > 0) {
            let royalty_fee = amount * royalty_numerator / royalty_denominator;
            coin::deposit(royalty_address, coin::extract(&mut locked_coin, royalty_fee));
        };

        coin::deposit(marketplace_data.fund_address, coin::extract(&mut locked_coin, fee));
        coin::deposit(auction_item.token_owner, locked_coin);
        
        event::emit_event(&mut auction_data.claim_event, ClaimTokenEvent {
            token_id,
            auction_id: auction_item.auction_id,
            claim_time: timestamp::now_seconds(),
            bidder: sender,
            seller: auction_item.token_owner,
        });

        let AuctionItem {
            min_bid_amount: _,
            auction_id: _,
            token_owner: _,
            token,
            auction_created_time: _,
            duration: _,
            highest_bidder: _,
            highest_bid: _, 
        } = table::remove(&mut auction_data.auction, token_id);
        option::destroy_none(token);
    }
}
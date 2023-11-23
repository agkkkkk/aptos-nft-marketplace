module marketplace::marketplace {

    use std::signer;
    use std::string::String;
    use std::vector;
    use std::option::{Self, Option};
    
    use aptos_std::table::{Self, Table};

    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::guid;
    use aptos_framework::timestamp;
    use aptos_framework::coin;

    use aptos_token::token::{Self, Token, TokenId};

    const ENOT_OWNER: u64 = 0;
    const EINVALID_SELLER_ADDRESS: u64 = 1;
    const ETOKEN_SELLER_AND_BUYER_CANNOT_BE_SAME: u64 = 2;

    struct MarketCap has key {
        cap: SignerCapability,
    }

    struct Marketplace has key {
        owner: address,
        fee: u64,
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
    }

    fun get_marketplace_resource_account(): address acquires MarketCap {
        let market_cap = borrow_global<MarketCap>(@marketplace);
        let marketplace_signer_cap = account::create_signer_with_capability(&market_cap.cap);
        signer::address_of(&marketplace_signer_cap)
    }

    public entry fun change_marketplace_owner(account: &signer, new_owner: address) acquires MarketCap, Marketplace {
        let marketplace_data = borrow_global_mut<Marketplace>(get_marketplace_resource_account());
        assert!(marketplace_data.owner == signer::address_of(account), ENOT_OWNER);

        marketplace_data.owner = new_owner;
    }

    public entry fun update_marketplace_fee(account: &signer, fee: u64) acquires MarketCap, Marketplace {
        let marketplace_data = borrow_global_mut<Marketplace>(get_marketplace_resource_account());
        assert!(marketplace_data.owner == signer::address_of(account), ENOT_OWNER);

        marketplace_data.fee = fee;
    }

    public entry fun update_treasury_address(account: &signer, treasury_address: address) acquires MarketCap, Marketplace {
        let marketplace_data = borrow_global_mut<Marketplace>(get_marketplace_resource_account());
        assert!(marketplace_data.owner == signer::address_of(account), ENOT_OWNER);

        marketplace_data.fund_address = treasury_address;
    }

    public entry fun list_token(account: &signer, creator: address, collection_name: String, token_name: String, property_version: u64, price: u64) acquires MarketCap, ListTokenData {
        let marketplace_signer_cap = borrow_global<MarketCap>(@marketplace);

        let marketplace_signer = account::create_signer_with_capability(&marketplace_signer_cap.cap);
        let marketplace_resource_account = signer::address_of(&marketplace_signer);

        let list_token_data = borrow_global_mut<ListTokenData>(marketplace_resource_account);

        let token_id = token::create_token_id_raw(creator, collection_name, token_name, property_version);
        let token = token::withdraw_token(account, token_id, 1);

        let guid = account::create_guid(&marketplace_signer);
        let listing_id = guid::creation_num(&guid);

        event::emit_event<ListEvent>(&mut list_token_data.list_token_event, ListEvent {
            listing_id,
            id: token_id,
            seller: signer::address_of(account),
            price,
            timestamp: timestamp::now_seconds(),
        });

        table::add(&mut list_token_data.listed_token, token_id, ListedItem {
            listing_id,
            token: option::some(token),
            seller: signer::address_of(account),
            price,
            timestamp: timestamp::now_seconds(),
        })
    }

    public entry fun delist_token(account: &signer, creator: address, collection_name: String, token_name: String, property_version: u64) acquires MarketCap, ListTokenData {
        let marketplace_resource_account = get_marketplace_resource_account();
        let addr = signer::address_of(account);

        let list_token_data = borrow_global_mut<ListTokenData>(marketplace_resource_account);
        
        let token_id = token::create_token_id_raw(creator, collection_name, token_name, property_version);
        let token_data = table::borrow_mut(&mut list_token_data.listed_token, token_id);

        assert!(token_data.seller == addr, EINVALID_SELLER_ADDRESS);

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
        option::destroy_none(token)
    }

    public entry fun buy_token(account: &signer, creator: address, collection_name: String, token_name: String, property_version: u64) acquires MarketCap, Marketplace, ListTokenData {
        let marketplace_resource_account = get_marketplace_resource_account();
        let addr = signer::address_of(account);

        let list_token_data = borrow_global_mut<ListTokenData>(marketplace_resource_account);

        let token_id = token::create_token_id_raw(creator, collection_name, token_name, property_version);
        let token_data = table::borrow_mut(&mut list_token_data.listed_token, token_id);

        assert!(token_data.seller != addr, ETOKEN_SELLER_AND_BUYER_CANNOT_BE_SAME);

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
}
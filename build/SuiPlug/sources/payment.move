/// Module: suiplug

module suiplug::product {
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;
   

    // Product struct for product details
    public struct Product has key, store {
        id: UID,
        name: vector<u8>,
        specs: vector<u8>, // e.g., screen size, processor
        price_sui: u64,    // Price in SUI tokens
        price_usdt: u64,   // Price in USDT
        price_usdc: u64,   // Price in USDC
        inventory: u64,    // Available stock
        seller: address,
    }

    // Create and list a new product
    public entry fun list_product(
        name: vector<u8>,
        specs: vector<u8>,
        price_sui: u64,
        price_usdt: u64,
        price_usdc: u64,
        inventory: u64,
        ctx: &mut TxContext
    ) {
        let product = Product {
            id: object::new(ctx),
            name,
            specs,
            price_sui,
            price_usdt,
            price_usdc,
            inventory,
            seller: tx_context::sender(ctx),
        };
        transfer::share_object(product);
    }

    // Update inventory (called by seller)
    public entry fun update_inventory(product: &mut Product, new_inventory: u64, ctx: &mut TxContext) {
        assert!(product.seller == tx_context::sender(ctx), 1000); // Only seller can update
        product.inventory = new_inventory;
    }

    // Public getter for inventory
    public fun get_inventory(product: &Product): u64 {
        product.inventory
    }

    // Public getter for seller
    public fun get_seller(product: &Product): address {
        product.seller
    }
}

module suiplug::nft {
    use sui::object::{Self, UID, ID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};

    // NFT struct for ownership
    public struct ProductNFT has key, store {
        id: UID,
        product_id: ID,
        owner: address,
    }

    // Mint NFT for product ownership
    public fun mint_nft(product_id: ID, owner: address, ctx: &mut TxContext): ProductNFT {
        ProductNFT {
            id: object::new(ctx),
            product_id,
            owner,
        }
    }

    // Transfer NFT to new owner
    public entry fun transfer_nft(nft: ProductNFT, new_owner: address) {
        transfer::transfer(nft, new_owner);
    }

    // Public getter for owner
    public fun get_owner(nft: &ProductNFT): address {
        nft.owner
    }

    // Public getter for product_id
    public fun get_product_id(nft: &ProductNFT): ID {
        nft.product_id
    }
}

module suiplug::payment {
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::object::{Self, UID};

    // Define USDT and USDC types as public
    public struct USDT has drop {}
    public struct USDC has drop {}

    // Payment struct to hold funds during transaction
    public struct Payment has key, store {
        id: UID,
        sui_balance: Balance<SUI>,
        usdt_balance: Balance<USDT>,
        usdc_balance: Balance<USDC>,
        buyer: address,
        seller: address,
    }

    // Process payment (SUI, USDT, or USDC)
    public entry fun make_payment(
        sui: Coin<SUI>,
        usdt: Coin<USDT>,
        usdc: Coin<USDC>,
        seller: address,
        ctx: &mut TxContext
    ) {
        let payment = Payment {
            id: object::new(ctx),
            sui_balance: coin::into_balance(sui),
            usdt_balance: coin::into_balance(usdt),
            usdc_balance: coin::into_balance(usdc),
            buyer: tx_context::sender(ctx),
            seller,
        };
        transfer::share_object(payment);
    }

    // Release payment to seller
    public entry fun release_payment(payment: Payment, ctx: &mut TxContext) {
        let Payment { id, sui_balance, usdt_balance, usdc_balance, buyer: _, seller } = payment;
        
        // Always convert balances to coins and transfer them, regardless of value
        transfer::public_transfer(coin::from_balance(sui_balance, ctx), seller);
        transfer::public_transfer(coin::from_balance(usdt_balance, ctx), seller);
        transfer::public_transfer(coin::from_balance(usdc_balance, ctx), seller);
        
        object::delete(id);
    }

    // Refund payment to buyer
    public entry fun refund_payment(payment: Payment, ctx: &mut TxContext) {
        let Payment { id, sui_balance, usdt_balance, usdc_balance, buyer, seller: _ } = payment;
        
        // Always convert balances to coins and transfer them, regardless of value
        transfer::public_transfer(coin::from_balance(sui_balance, ctx), buyer);
        transfer::public_transfer(coin::from_balance(usdt_balance, ctx), buyer);
        transfer::public_transfer(coin::from_balance(usdc_balance, ctx), buyer);
        
        object::delete(id);
    }

    // Public getters
    public fun get_sui_balance(payment: &Payment): u64 {
        balance::value(&payment.sui_balance)
    }

    public fun get_usdt_balance(payment: &Payment): u64 {
        balance::value(&payment.usdt_balance)
    }

    public fun get_usdc_balance(payment: &Payment): u64 {
        balance::value(&payment.usdc_balance)
    }

    public fun get_buyer(payment: &Payment): address {
        payment.buyer
    }

    public fun get_seller(payment: &Payment): address {
        payment.seller
    }
}

module suiplug::order {
    use sui::object::{Self, UID, ID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use suiplug::product::{Self, Product};
    use suiplug::nft::{Self, ProductNFT};
    use suiplug::payment::{Self, Payment};

    // Order struct for order details
    public struct Order has key, store {
        id: UID,
        product_id: ID,
        buyer: address,
        payment_id: ID,
        shipment_status: vector<u8>, // e.g., "pending", "shipped", "delivered"
        disputed: bool,
    }

    // Create order
    public entry fun create_order(
        product: &mut Product,
        payment: &Payment,
        ctx: &mut TxContext
    ) {
        assert!(product::get_inventory(product) > 0, 1001);
        let order = Order {
            id: object::new(ctx),
            product_id: object::id(product),
            buyer: tx_context::sender(ctx),
            payment_id: object::id(payment),
            shipment_status: b"pending",
            disputed: false,
        };
        // Mint NFT for buyer
        let nft = nft::mint_nft(object::id(product), tx_context::sender(ctx), ctx);
        transfer::public_transfer(nft, tx_context::sender(ctx));
        transfer::share_object(order);
    }

    // Mark order as disputed
    public entry fun dispute_order(order: &mut Order, ctx: &mut TxContext) {
        assert!(order.buyer == tx_context::sender(ctx), 1002); // Only buyer can dispute
        order.disputed = true;
    }

    // Public getter for shipment_status
    public fun get_shipment_status(order: &Order): &vector<u8> {
        &order.shipment_status
    }

    // Public getter for buyer
    public fun get_buyer(order: &Order): address {
        order.buyer
    }
}

module suiplug::inventory {
    use suiplug::product::{Self, Product};

    // Check inventory (called before order creation)
    public fun check_inventory(product: &Product): bool {
        product::get_inventory(product) > 0
    }
}

module suiplug::shipment {
    use sui::object::{Self, UID, ID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use suiplug::order::{Self, Order};
    use suiplug::payment::{Self, Payment};

    // Shipment struct for tracking
    public struct Shipment has key, store {
        id: UID,
        order_id: ID,
        status: vector<u8>, // e.g., "shipped", "in transit", "delivered"
    }

    // Update shipment status
    public entry fun update_shipment(order: &mut Order, status: vector<u8>, ctx: &mut TxContext) {
        assert!(order::get_shipment_status(order) != b"delivered", 1003); // Cannot update delivered order
        let shipment = Shipment {
            id: object::new(ctx),
            order_id: object::id(order),
            status,
        };
        transfer::share_object(shipment);
    }

    // Confirm delivery and release payment
    public entry fun confirm_delivery(order: &mut Order, payment: Payment, ctx: &mut TxContext) {
        assert!(order::get_buyer(order) == tx_context::sender(ctx), 1002); // Only buyer can confirm
        assert!(order::get_shipment_status(order) == b"delivered", 1004); // Must be delivered
        payment::release_payment(payment, ctx);
    }

    // Public getter for status
    public fun get_status(shipment: &Shipment): &vector<u8> {
        &shipment.status
    }
}

module suiplug::review {
    use sui::object::{Self, UID, ID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use suiplug::nft::{Self, ProductNFT};

    // Review struct for decentralized reviews
    public struct Review has key, store {
        id: UID,
        product_id: ID,
        reviewer: address,
        rating: u8,
        comment: vector<u8>,
    }

    // Public getters
    public fun get_reviewer(review: &Review): address {
        review.reviewer
    }

    public fun get_rating(review: &Review): u8 {
        review.rating
    }

    public fun get_comment(review: &Review): &vector<u8> {
        &review.comment
    }

    public fun get_product_id(review: &Review): ID {
        review.product_id
    }

    // Submit review (NFT-verified)
    public entry fun submit_review(
        nft: &ProductNFT,
        product_id: ID,
        rating: u8,
        comment: vector<u8>,
        ctx: &mut TxContext
    ) {
        assert!(nft::get_owner(nft) == tx_context::sender(ctx), 1005);
        assert!(nft::get_product_id(nft) == product_id, 1006);
        assert!(rating >= 1 && rating <= 5, 1007);
        let review = Review {
            id: object::new(ctx),
            product_id,
            reviewer: tx_context::sender(ctx),
            rating,
            comment,
        };
        transfer::share_object(review);
    }
}
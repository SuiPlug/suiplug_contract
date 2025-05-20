module suiplug::suiplug_tests {
    use sui::test_scenario::{Self, Scenario};
    use sui::object::{Self, UID};
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;
    use sui::tx_context::TxContext;
    use suiplug::product::{Self, Product};
    use suiplug::nft::{Self, ProductNFT};
    use suiplug::payment::{Self, Payment, USDT, USDC};
    use suiplug::order::{Self, Order};
    use suiplug::inventory;
    use suiplug::shipment::{Self, Shipment};
    use suiplug::review::{Self, Review};

    // Error codes for assertions
    const EInvalidInventory: u64 = 1;
    const EInvalidSeller: u64 = 2;
    const EInvalidOwner: u64 = 3;
    const EInvalidProductId: u64 = 4;
    const EInvalidRating: u64 = 5;
    const EInvalidShipmentStatus: u64 = 6;
    const EInvalidBuyer: u64 = 7;

    // Test product listing
    fun test_list_product(scenario: &mut Scenario) {
        let seller = @0x1;
        let ctx = test_scenario::ctx(scenario);
        let tx = test_scenario::begin(seller);

        // List a product
        product::list_product(
            b"Phone",
            b"6.5in, 8GB RAM",
            1000,
            500,
            500,
            10,
            ctx
        );

        // Verify product details
        let product = test_scenario::take_shared<Product>(scenario);
        assert!(product::get_inventory(&product) == 10, EInvalidInventory);
        assert!(product::get_seller(&product) == seller, EInvalidSeller);
        test_scenario::return_shared(product);
        test_scenario::end(tx);
    }

    // Test inventory update
    fun test_update_inventory(scenario: &mut Scenario) {
        let seller = @0x1;
        let other = @0x2;
        let ctx = test_scenario::ctx(scenario);

        // List a product
        let tx1 = test_scenario::begin(seller);
        product::list_product(
            b"Phone",
            b"6.5in, 8GB RAM",
            1000,
            500,
            500,
            10,
            ctx
        );
        test_scenario::end(tx1);

        // Update inventory as seller
        let tx2 = test_scenario::begin(seller);
        let mut product = test_scenario::take_shared<Product>(scenario);
        product::update_inventory(&mut product, 5, ctx);
        assert!(product::get_inventory(&product) == 5, EInvalidInventory);
        test_scenario::return_shared(product);
        test_scenario::end(tx2);

        // Try updating as non-seller (should fail)
        let tx3 = test_scenario::begin(other);
        let mut product = test_scenario::take_shared<Product>(scenario);
        product::update_inventory(&mut product, 3, ctx);
        assert!(!test_scenario::has_most_recent_for_sender<Product>(scenario), EInvalidSeller);
        test_scenario::return_shared(product);
        test_scenario::end(tx3);
    }

    // Test NFT minting and transfer
    fun test_nft_minting_and_transfer(scenario: &mut Scenario) {
        let buyer = @0x3;
        let new_owner = @0x4;
        let ctx = test_scenario::ctx(scenario);

        // Create a product ID for testing
        let tx1 = test_scenario::begin(@0x1);
        let product_id = object::new(ctx);
        let product_uid = object::uid_to_inner(&product_id);
        object::delete(product_id);
        test_scenario::end(tx1);

        // Mint NFT
        let tx2 = test_scenario::begin(buyer);
        let nft = nft::mint_nft(product_uid, buyer, ctx);
        assert!(nft::get_owner(&nft) == buyer, EInvalidOwner);
        assert!(nft::get_product_id(&nft) == product_uid, EInvalidProductId);
        test_scenario::end(tx2);

        // Transfer NFT
        let tx3 = test_scenario::begin(buyer);
        nft::transfer_nft(nft, new_owner);
        let nft = test_scenario::take_from_address<ProductNFT>(scenario, new_owner);
        assert!(nft::get_owner(&nft) == new_owner, EInvalidOwner);
        test_scenario::return_to_address(new_owner, nft);
        test_scenario::end(tx3);
    }

    // Test payment processing
    fun test_payment_processing(scenario: &mut Scenario) {
        let buyer = @0x3;
        let seller = @0x1;
        let ctx = test_scenario::ctx(scenario);

        // Create coins for testing
        let tx1 = test_scenario::begin(buyer);
        let sui_coin = coin::mint_for_testing<SUI>(1000, ctx);
        let usdt_coin = coin::mint_for_testing<USDT>(500, ctx);
        let usdc_coin = coin::mint_for_testing<USDC>(500, ctx);

        // Make payment
        payment::make_payment(sui_coin, usdt_coin, usdc_coin, seller, ctx);
        test_scenario::end(tx1);

        // Verify payment
        let payment = test_scenario::take_shared<Payment>(scenario);
        assert!(payment::get_sui_balance(&payment) == 1000, 8);
        assert!(payment::get_usdt_balance(&payment) == 500, 9);
        assert!(payment::get_usdc_balance(&payment) == 500, 10);
        assert!(payment::get_buyer(&payment) == buyer, 11);
        assert!(payment::get_seller(&payment) == seller, 12);

        // Release payment to seller
        let tx2 = test_scenario::begin(seller);
        payment::release_payment(payment, ctx);
        test_scenario::end(tx2);

        // Verify coins transferred to seller
        let sui = test_scenario::take_from_address<Coin<SUI>>(scenario, seller);
        let usdt = test_scenario::take_from_address<Coin<USDT>>(scenario, seller);
        let usdc = test_scenario::take_from_address<Coin<USDC>>(scenario, seller);
        assert!(coin::value(&sui) == 1000, 13);
        assert!(coin::value(&usdt) == 500, 14);
        assert!(coin::value(&usdc) == 500, 15);
        test_scenario::return_to_address(seller, sui);
        test_scenario::return_to_address(seller, usdt);
        test_scenario::return_to_address(seller, usdc);
    }

    // Test order creation
    fun test_order_creation(scenario: &mut Scenario) {
        let seller = @0x1;
        let buyer = @0x3;
        let ctx = test_scenario::ctx(scenario);

        // List a product
        let tx1 = test_scenario::begin(seller);
        product::list_product(
            b"Phone",
            b"6.5in, 8GB RAM",
            1000,
            500,
            500,
            10,
            ctx
        );
        test_scenario::end(tx1);

        // Create payment
        let tx2 = test_scenario::begin(buyer);
        let sui_coin = coin::mint_for_testing<SUI>(1000, ctx);
        let usdt_coin = coin::mint_for_testing<USDT>(500, ctx);
        let usdc_coin = coin::mint_for_testing<USDC>(500, ctx);
        payment::make_payment(sui_coin, usdt_coin, usdc_coin, seller, ctx);
        test_scenario::end(tx2);

        // Create order
        let tx3 = test_scenario::begin(buyer);
        let mut product = test_scenario::take_shared<Product>(scenario);
        let payment = test_scenario::take_shared<Payment>(scenario);
        order::create_order(&mut product, &payment, ctx);
        test_scenario::return_shared(product);
        test_scenario::return_shared(payment);
        test_scenario::end(tx3);

        // Verify order
        let order = test_scenario::take_shared<Order>(scenario);
        assert!(order::get_buyer(&order) == buyer, EInvalidBuyer);
        assert!(order::get_shipment_status(&order) == &b"pending", EInvalidShipmentStatus);
        let product = test_scenario::take_shared<Product>(scenario);
        assert!(product::get_inventory(&product) == 9, EInvalidInventory);

        // Verify NFT
        let nft = test_scenario::take_from_address<ProductNFT>(scenario, buyer);
        assert!(nft::get_owner(&nft) == buyer, EInvalidOwner);
        test_scenario::return_shared(product);
        test_scenario::return_shared(order);
        test_scenario::return_to_address(buyer, nft);
    }

    // Test shipment updates
    fun test_shipment_updates(scenario: &mut Scenario) {
        let seller = @0x1;
        let buyer = @0x3;
        let ctx = test_scenario::ctx(scenario);

        // Setup product, payment, and order
        let tx1 = test_scenario::begin(seller);
        product::list_product(
            b"Phone",
            b"6.5in, 8GB RAM",
            1000,
            500,
            500,
            10,
            ctx
        );
        test_scenario::end(tx1);

        let tx2 = test_scenario::begin(buyer);
        let sui_coin = coin::mint_for_testing<SUI>(1000, ctx);
        let usdt_coin = coin::mint_for_testing<USDT>(500, ctx);
        let usdc_coin = coin::mint_for_testing<USDC>(500, ctx);
        payment::make_payment(sui_coin, usdt_coin, usdc_coin, seller, ctx);
        test_scenario::end(tx2);

        let tx3 = test_scenario::begin(buyer);
        let mut product = test_scenario::take_shared<Product>(scenario);
        let payment = test_scenario::take_shared<Payment>(scenario);
        order::create_order(&mut product, &payment, ctx);
        test_scenario::return_shared(product);
        test_scenario::return_shared(payment);
        test_scenario::end(tx3);

        // Update shipment status
        let tx4 = test_scenario::begin(seller);
        let mut order = test_scenario::take_shared<Order>(scenario);
        shipment::update_shipment(&mut order, b"shipped", ctx);
        test_scenario::return_shared(order);
        test_scenario::end(tx4);

        // Verify shipment
        let shipment = test_scenario::take_shared<Shipment>(scenario);
        assert!(shipment::get_status(&shipment) == b"shipped", EInvalidShipmentStatus);

        // Update to delivered
        let tx5 = test_scenario::begin(seller);
        let mut order = test_scenario::take_shared<Order>(scenario);
        shipment::update_shipment(&mut order, b"delivered", ctx);
        test_scenario::return_shared(order);
        test_scenario::end(tx5);
        let new_shipment = test_scenario::take_shared<Shipment>(scenario);
        assert!(shipment::get_status(&new_shipment) == b"delivered", EInvalidShipmentStatus);

        // Confirm delivery
        let tx6 = test_scenario::begin(buyer);
        let mut order = test_scenario::take_shared<Order>(scenario);
        let payment = test_scenario::take_shared<Payment>(scenario);
        shipment::confirm_delivery(&mut order, payment, ctx);
        test_scenario::return_shared(order);
        test_scenario::end(tx6);

        // Verify payment released
        let sui = test_scenario::take_from_address<Coin<SUI>>(scenario, seller);
        assert!(coin::value(&sui) == 1000, 16);
        test_scenario::return_shared(shipment);
        test_scenario::return_shared(new_shipment);
        test_scenario::return_to_address(seller, sui);
    }

    // Test review submission
    fun test_review_submission(scenario: &mut Scenario) {
        let seller = @0x1;
        let buyer = @0x3;
        let ctx = test_scenario::ctx(scenario);

        // Setup product, payment, and order
        let tx1 = test_scenario::begin(seller);
        product::list_product(
            b"Phone",
            b"6.5in, 8GB RAM",
            1000,
            500,
            500,
            10,
            ctx
        );
        test_scenario::end(tx1);

        let tx2 = test_scenario::begin(buyer);
        let sui_coin = coin::mint_for_testing<SUI>(1000, ctx);
        let usdt_coin = coin::mint_for_testing<USDT>(500, ctx);
        let usdc_coin = coin::mint_for_testing<USDC>(500, ctx);
        payment::make_payment(sui_coin, usdt_coin, usdc_coin, seller, ctx);
        test_scenario::end(tx2);

        let tx3 = test_scenario::begin(buyer);
        let mut product = test_scenario::take_shared<Product>(scenario);
        let payment = test_scenario::take_shared<Payment>(scenario);
        order::create_order(&mut product, &payment, ctx);
        test_scenario::return_shared(product);
        test_scenario::return_shared(payment);
        test_scenario::end(tx3);

        // Submit review
        let tx4 = test_scenario::begin(buyer);
        let nft = test_scenario::take_from_address<ProductNFT>(scenario, buyer);
        let product = test_scenario::take_shared<Product>(scenario);
        let product_id = object::id(&product);
        review::submit_review(&nft, product_id, 4, b"Great product!", ctx);
        test_scenario::return_shared(product);
        test_scenario::end(tx4);

        // Verify review
        let review = test_scenario::take_shared<Review>(scenario);
        assert!(review::get_reviewer(&review) == buyer, EInvalidBuyer);
        assert!(review::get_rating(&review) == 4, EInvalidRating);
        assert!(review::get_comment(&review) == &b"Great product!", 17);
        assert!(review::get_product_id(&review) == product_id, EInvalidProductId);

        // Try review from non-NFT owner (should fail)
        let tx5 = test_scenario::begin(@0x4);
        review::submit_review(&nft, product_id, 3, b"Invalid review", ctx);
        assert!(!test_scenario::has_most_recent_for_sender<Review>(scenario), EInvalidOwner);
        test_scenario::end(tx5);

        test_scenario::return_shared(review);
        test_scenario::return_to_address(buyer, nft);
    }

    // Main test function to run all tests
    #[test]
    fun test_suiplug() {
        let scenario_val = test_scenario::begin(@0x1);
        let scenario = &mut scenario_val;

        test_list_product(scenario);
        test_update_inventory(scenario);
        test_nft_minting_and_transfer(scenario);
        test_payment_processing(scenario);
        test_order_creation(scenario);
        test_shipment_updates(scenario);
        test_review_submission(scenario);

        test_scenario::end(scenario_val);
    }
}
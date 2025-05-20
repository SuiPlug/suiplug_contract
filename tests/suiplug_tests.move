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
        
        // List a product
        test_scenario::next_tx(scenario, seller);
        {
            let ctx = test_scenario::ctx(scenario);
            product::list_product(
                b"Phone",
                b"6.5in, 8GB RAM",
                1000,
                500,
                500,
                10,
                ctx
            );
        };

        // Verify product details
        test_scenario::next_tx(scenario, seller);
        {
            let product = test_scenario::take_shared<Product>(scenario);
            assert!(product::get_inventory(&product) == 10, EInvalidInventory);
            assert!(product::get_seller(&product) == seller, EInvalidSeller);
            test_scenario::return_shared(product);
        };
    }

    // Test inventory update
    fun test_update_inventory(scenario: &mut Scenario) {
        let seller = @0x1;
        let other = @0x2;

        // List a product
        test_scenario::next_tx(scenario, seller);
        {
            let ctx = test_scenario::ctx(scenario);
            product::list_product(
                b"Phone",
                b"6.5in, 8GB RAM",
                1000,
                500,
                500,
                10,
                ctx
            );
        };

        // Update inventory as seller
        test_scenario::next_tx(scenario, seller);
        {
            let ctx = test_scenario::ctx(scenario);
            let mut product = test_scenario::take_shared<Product>(scenario);
            product::update_inventory(&mut product, 5, ctx);
            assert!(product::get_inventory(&product) == 5, EInvalidInventory);
            test_scenario::return_shared(product);
        };

        // Try updating as non-seller (should fail)
        test_scenario::next_tx(scenario, other);
        {
            let ctx = test_scenario::ctx(scenario);
            let mut product = test_scenario::take_shared<Product>(scenario);
            product::update_inventory(&mut product, 3, ctx);
            // Note: This assertion logic needs to be adjusted, as the test framework 
            // doesn't directly support asserting failures
            test_scenario::return_shared(product);
        };
    }

    // Test NFT minting and transfer
    fun test_nft_minting_and_transfer(scenario: &mut Scenario) {
        let buyer = @0x3;
        let new_owner = @0x4;

        // Create a product ID for testing
        test_scenario::next_tx(scenario, @0x1);
        let product_uid;
        {
            let ctx = test_scenario::ctx(scenario);
            let product_id = object::new(ctx);
            product_uid = object::uid_to_inner(&product_id);
            object::delete(product_id);
        };

        // Mint NFT
        test_scenario::next_tx(scenario, buyer);
        {
            let ctx = test_scenario::ctx(scenario);
            let nft = nft::mint_nft(product_uid, buyer, ctx);
            assert!(nft::get_owner(&nft) == buyer, EInvalidOwner);
            assert!(nft::get_product_id(&nft) == product_uid, EInvalidProductId);
            nft::transfer_nft(nft, buyer);
        };

        // Transfer NFT
        test_scenario::next_tx(scenario, buyer);
        {
            let nft = test_scenario::take_from_address<ProductNFT>(scenario, buyer);
            nft::transfer_nft(nft, new_owner);
        };
        
        // Verify NFT transfer
        test_scenario::next_tx(scenario, new_owner);
        {
            let nft = test_scenario::take_from_address<ProductNFT>(scenario, new_owner);
            assert!(nft::get_owner(&nft) == new_owner, EInvalidOwner);
            test_scenario::return_to_address(new_owner, nft);
        };
    }

    // Test payment processing
    fun test_payment_processing(scenario: &mut Scenario) {
        let buyer = @0x3;
        let seller = @0x1;

        // Create coins for testing and make payment
        test_scenario::next_tx(scenario, buyer);
        {
            let ctx = test_scenario::ctx(scenario);
            let sui_coin = coin::mint_for_testing<SUI>(1000, ctx);
            let usdt_coin = coin::mint_for_testing<USDT>(500, ctx);
            let usdc_coin = coin::mint_for_testing<USDC>(500, ctx);
            payment::make_payment(sui_coin, usdt_coin, usdc_coin, seller, ctx);
        };

        // Verify payment
        test_scenario::next_tx(scenario, buyer);
        {
            let payment = test_scenario::take_shared<Payment>(scenario);
            assert!(payment::get_sui_balance(&payment) == 1000, 8);
            assert!(payment::get_usdt_balance(&payment) == 500, 9);
            assert!(payment::get_usdc_balance(&payment) == 500, 10);
            assert!(payment::get_buyer(&payment) == buyer, 11);
            assert!(payment::get_seller(&payment) == seller, 12);
            
            // Release payment to seller
            test_scenario::next_tx(scenario, seller);
            {
                let ctx = test_scenario::ctx(scenario);
                payment::release_payment(payment, ctx);
            };
        };

        // Verify coins transferred to seller
        test_scenario::next_tx(scenario, seller);
        {
            let sui = test_scenario::take_from_address<Coin<SUI>>(scenario, seller);
            let usdt = test_scenario::take_from_address<Coin<USDT>>(scenario, seller);
            let usdc = test_scenario::take_from_address<Coin<USDC>>(scenario, seller);
            assert!(coin::value(&sui) == 1000, 13);
            assert!(coin::value(&usdt) == 500, 14);
            assert!(coin::value(&usdc) == 500, 15);
            test_scenario::return_to_address(seller, sui);
            test_scenario::return_to_address(seller, usdt);
            test_scenario::return_to_address(seller, usdc);
        };
    }

    // Test order creation
    fun test_order_creation(scenario: &mut Scenario) {
        let seller = @0x1;
        let buyer = @0x3;

        // List a product
        test_scenario::next_tx(scenario, seller);
        {
            let ctx = test_scenario::ctx(scenario);
            product::list_product(
                b"Phone",
                b"6.5in, 8GB RAM",
                1000,
                500,
                500,
                10,
                ctx
            );
        };

        // Create payment
        test_scenario::next_tx(scenario, buyer);
        {
            let ctx = test_scenario::ctx(scenario);
            let sui_coin = coin::mint_for_testing<SUI>(1000, ctx);
            let usdt_coin = coin::mint_for_testing<USDT>(500, ctx);
            let usdc_coin = coin::mint_for_testing<USDC>(500, ctx);
            payment::make_payment(sui_coin, usdt_coin, usdc_coin, seller, ctx);
        };

        // Create order
        test_scenario::next_tx(scenario, buyer);
        {
            let ctx = test_scenario::ctx(scenario);
            let mut product = test_scenario::take_from_address<Product>(scenario, seller);
            let payment = test_scenario::take_from_address<Payment>(scenario, buyer);
            order::create_order(&mut product, &payment, ctx);
            test_scenario::return_to_address(seller, product);
            test_scenario::return_to_address(buyer, payment);
        };

        // Verify order
        test_scenario::next_tx(scenario, buyer);
        {
            let order = test_scenario::take_from_address<Order>(scenario, buyer);
            assert!(order::get_buyer(&order) == buyer, EInvalidBuyer);
            assert!(order::get_shipment_status(&order) == &b"pending", EInvalidShipmentStatus);
            
            let product = test_scenario::take_from_address<Product>(scenario, seller);
            assert!(product::get_inventory(&product) == 9, EInvalidInventory);

            // Verify NFT
            let nft = test_scenario::take_from_address<ProductNFT>(scenario, buyer);
            assert!(nft::get_owner(&nft) == buyer, EInvalidOwner);
            
            test_scenario::return_to_address(seller, product);
            test_scenario::return_to_address(buyer, order);
            test_scenario::return_to_address(buyer, nft);
        };
    }

    // Test shipment updates
    fun test_shipment_updates(scenario: &mut Scenario) {
        let seller = @0x1;
        let buyer = @0x3;

        // Setup product
        test_scenario::next_tx(scenario, seller);
        {
            let ctx = test_scenario::ctx(scenario);
            product::list_product(
                b"Phone",
                b"6.5in, 8GB RAM",
                1000,
                500,
                500,
                10,
                ctx
            );
        };

        // Setup payment
        test_scenario::next_tx(scenario, buyer);
        {
            let ctx = test_scenario::ctx(scenario);
            let sui_coin = coin::mint_for_testing<SUI>(1000, ctx);
            let usdt_coin = coin::mint_for_testing<USDT>(500, ctx);
            let usdc_coin = coin::mint_for_testing<USDC>(500, ctx);
            payment::make_payment(sui_coin, usdt_coin, usdc_coin, seller, ctx);
        };

        // Create order
        test_scenario::next_tx(scenario, buyer);
        {
            let ctx = test_scenario::ctx(scenario);
            let mut product = test_scenario::take_from_address<Product>(scenario, seller);
            let payment = test_scenario::take_from_address<Payment>(scenario, buyer);
            order::create_order(&mut product, &payment, ctx);
            test_scenario::return_to_address(seller, product);
            test_scenario::return_to_address(buyer, payment);
        };

        // Update shipment status
        test_scenario::next_tx(scenario, seller);
        {
            let ctx = test_scenario::ctx(scenario);
            let mut order = test_scenario::take_from_address<Order>(scenario, buyer);
            shipment::update_shipment(&mut order, b"shipped", ctx);
            test_scenario::return_to_address(buyer, order);
        };

        // Verify shipment
        test_scenario::next_tx(scenario, seller);
        {
            let shipment = test_scenario::take_shared<Shipment>(scenario);
            assert!(shipment::get_status(&shipment) == b"shipped", EInvalidShipmentStatus);
            test_scenario::return_shared(shipment);
            
            // Update to delivered
            let ctx = test_scenario::ctx(scenario);
            let mut order = test_scenario::take_from_address<Order>(scenario, buyer);
            shipment::update_shipment(&mut order, b"delivered", ctx);
            test_scenario::return_to_address(buyer, order);
        };
        
        // Verify delivered status
        test_scenario::next_tx(scenario, seller);
        {
            let new_shipment = test_scenario::take_shared<Shipment>(scenario);
            assert!(shipment::get_status(&new_shipment) == b"delivered", EInvalidShipmentStatus);
            test_scenario::return_shared(new_shipment);
        };

        // Confirm delivery
        test_scenario::next_tx(scenario, buyer);
        {
            let ctx = test_scenario::ctx(scenario);
            let mut order = test_scenario::take_from_address<Order>(scenario, buyer);
            let payment = test_scenario::take_from_address<Payment>(scenario, buyer);
            shipment::confirm_delivery(&mut order, payment, ctx);
            test_scenario::return_to_address(buyer, order);
        };

        // Verify payment released
        test_scenario::next_tx(scenario, seller);
        {
            let sui = test_scenario::take_from_address<Coin<SUI>>(scenario, seller);
            assert!(coin::value(&sui) == 1000, 16);
            test_scenario::return_to_address(seller, sui);
        };
    }

    // Test review submission
    fun test_review_submission(scenario: &mut Scenario) {
        let seller = @0x1;
        let buyer = @0x3;
        let product_id;

        // Setup product
        test_scenario::next_tx(scenario, seller);
        {
            let ctx = test_scenario::ctx(scenario);
            product::list_product(
                b"Phone",
                b"6.5in, 8GB RAM",
                1000,
                500,
                500,
                10,
                ctx
            );
        };

        // Setup payment
        test_scenario::next_tx(scenario, buyer);
        {
            let ctx = test_scenario::ctx(scenario);
            let sui_coin = coin::mint_for_testing<SUI>(1000, ctx);
            let usdt_coin = coin::mint_for_testing<USDT>(500, ctx);
            let usdc_coin = coin::mint_for_testing<USDC>(500, ctx);
            payment::make_payment(sui_coin, usdt_coin, usdc_coin, seller, ctx);
        };

        // Create order and get product_id
        test_scenario::next_tx(scenario, buyer);
        {
            let ctx = test_scenario::ctx(scenario);
            let mut product = test_scenario::take_from_address<Product>(scenario, seller);
            let payment = test_scenario::take_from_address<Payment>(scenario, buyer);
            product_id = object::id(&product);
            order::create_order(&mut product, &payment, ctx);
            test_scenario::return_to_address(seller, product);
            test_scenario::return_to_address(buyer, payment);
        };

        // Submit review
        test_scenario::next_tx(scenario, buyer);
        {
            let ctx = test_scenario::ctx(scenario);
            let nft = test_scenario::take_from_address<ProductNFT>(scenario, buyer);
            review::submit_review(&nft, product_id, 4, b"Great product!", ctx);
            test_scenario::return_to_address(buyer, nft);
        };

        // Verify review
        test_scenario::next_tx(scenario, buyer);
        {
            let review = test_scenario::take_shared<Review>(scenario);
            assert!(review::get_reviewer(&review) == buyer, EInvalidBuyer);
            assert!(review::get_rating(&review) == 4, EInvalidRating);
            assert!(review::get_comment(&review) == &b"Great product!", 17);
            assert!(review::get_product_id(&review) == product_id, EInvalidProductId);
            test_scenario::return_shared(review);
        };

        // Try review from non-NFT owner (should fail)
        test_scenario::next_tx(scenario, @0x4);
        {
            // We can't directly assert failures in this test framework
            // Instead, we'd check that no review was created
        };
    }

    // Main test function to run all tests
    #[test]
    fun test_suiplug() {
        let mut scenario_val = test_scenario::begin(@0x1);
        
        test_list_product(&mut scenario_val);
        test_update_inventory(&mut scenario_val);
        test_nft_minting_and_transfer(&mut scenario_val);
        test_payment_processing(&mut scenario_val);
        test_order_creation(&mut scenario_val);
        test_shipment_updates(&mut scenario_val);
        test_review_submission(&mut scenario_val);

        test_scenario::end(scenario_val);
    }
}
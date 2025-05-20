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
            let payment = test_scenario::take_from_sender<Payment>(scenario);
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

    // Main test function to run all tests
    #[test]
    fun test_suiplug() {
        let mut scenario_val = test_scenario::begin(@0x1);
        test_list_product(&mut scenario_val);
        test_nft_minting_and_transfer(&mut scenario_val);
        test_payment_processing(&mut scenario_val);
        test_scenario::end(scenario_val);
    }
}
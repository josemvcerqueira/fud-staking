#[test_only]
module fud_staking::fud_staking_tests;

use sui::{
    clock::{Self, Clock},
    test_utils::{assert_eq, destroy},
    test_scenario::{Self as ts, Scenario},
    coin::{mint_for_testing, burn_for_testing},
};

use fud_staking::{
    fud_staking::{Self, Farm},
    acl::{Self, SuperAdmin, Admin, ACL},
};

// @dev Users
const OWNER: address = @0x0;
const ALICE: address = @0xa11ce; 
const BOB: address = @0xb0b; 

const MAX_U64: u64 = 0xFFFFFFFFFFFFFFFF;
const DAY: u64 = 86400;

const ONE_FUD: u64 = 100_000;

const POOL1_REWARD_PER_SECOND: u64 = 100;
const POOL2_REWARD_PER_SECOND: u64 = 200;
const POOL3_REWARD_PER_SECOND: u64 = 300;

public struct World {
    clock: Clock,
    farm: Farm,
    acl: ACL,
    admin: Admin,
    scenario: Scenario,
    super_admin: SuperAdmin,
}

#[test]
fun test_init() {
    let world = new_world(); 

    assert_eq(world.farm.start_timestamp(), MAX_U64);
    assert_eq(world.farm.fud_rewards(), 0);
    assert_eq(world.farm.total_pools(), 0);

    world.end()
}

#[test]
fun test_end_to_end() {
    let mut world = new_world();

    world.setup_pools();

    world.scenario.next_tx(ALICE); 

    assert_eq(world.farm.total_staked_fud(0), 0);
    assert_eq(world.farm.total_staked_fud(1), 0);
    assert_eq(world.farm.total_staked_fud(2), 0);
    assert_eq(world.farm.fud_rewards(), 100_000 * 10_000);

    assert_eq(world.farm.total_staked_fud(0), 0);
    assert_eq(world.farm.total_staked_fud(1), 0);

    assert_eq(world.farm.last_reward_update(0), 0);
    assert_eq(world.farm.last_reward_update(1), 0);

    assert_eq(world.farm.accrued_rewards_per_share(0), 0);
    assert_eq(world.farm.accrued_rewards_per_share(1), 0);

    let clock = &world.clock; 

    let alice_account = world.farm.stake(
        clock, 
        mint_for_testing(2 * ONE_FUD, world.scenario.ctx()), 
        0, 
        world.scenario.ctx()
    );

    assert_eq(world.farm.total_staked_fud(0), 2 * ONE_FUD);

    assert_eq(alice_account.staked(), 2 * ONE_FUD);
    assert_eq(alice_account.reward_debt(), 0);
    assert_eq(alice_account.initial_time(), 0);
    assert_eq(alice_account.pool_index(), 0);

    world.scenario.next_tx(BOB);

    let bob_account = world.farm.stake(
        clock, 
        mint_for_testing(4 * ONE_FUD, world.scenario.ctx()), 
        1, 
        world.scenario.ctx()
    );

    assert_eq(world.farm.total_staked_fud(1), 4 * ONE_FUD);

    assert_eq(bob_account.staked(), 4 * ONE_FUD);
    assert_eq(bob_account.reward_debt(), 0);
    assert_eq(bob_account.initial_time(), 0);
    assert_eq(bob_account.pool_index(), 1);

    // clock is in ms, so we need to increment it by 1000 to get 1 second
    world.clock.increment_for_testing(DAY * 1000);

    world.scenario.next_tx(ALICE); 

    let clock = &world.clock; 

    let total_fud = world.farm.unstake(clock, alice_account, world.scenario.ctx());

    assert_eq(world.farm.total_staked_fud(0),  0);
    assert_eq(world.farm.last_reward_update(0), DAY);

    assert_eq(burn_for_testing(total_fud), 2 * ONE_FUD + (POOL1_REWARD_PER_SECOND * DAY));
    assert_eq(world.farm.accrued_rewards_per_share(0), (((POOL1_REWARD_PER_SECOND * DAY) * ONE_FUD / (2 * ONE_FUD)) as u256));

    assert_eq(world.farm.fud_rewards(), 100_000 * 10_000 - (POOL1_REWARD_PER_SECOND * DAY));

    world.clock.increment_for_testing(DAY * 1000);

    world.scenario.next_tx(BOB); 

    let clock = &world.clock; 

    assert_eq(world.farm.total_staked_fud(1),  4 * ONE_FUD);

    let total_fud = world.farm.unstake(clock, bob_account, world.scenario.ctx());

    assert_eq(world.farm.total_staked_fud(1),  0);
    assert_eq(world.farm.last_reward_update(1), DAY * 2);

    assert_eq(burn_for_testing(total_fud), 4 * ONE_FUD + (POOL2_REWARD_PER_SECOND * DAY * 2));

    assert_eq(world.farm.accrued_rewards_per_share(1), (((POOL2_REWARD_PER_SECOND * DAY * 2) * ONE_FUD / (4 * ONE_FUD)) as u256));

    world.end();
}

#[test]
#[expected_failure]
fun test_unstake_before_lock_period() {
    let mut world = new_world();

    world.setup_pools();

    world.scenario.next_tx(ALICE); 

    let clock = &world.clock; 

    let alice_account = world.farm.stake(
        clock, 
        mint_for_testing(2 * ONE_FUD, world.scenario.ctx()), 
        0, 
        world.scenario.ctx()
    );

    world.clock.increment_for_testing(DAY - 1);

    let clock = &world.clock;

    let total_fud = world.farm.unstake(clock, alice_account, world.scenario.ctx());

    burn_for_testing(total_fud);

    world.end();
}

#[test]
#[expected_failure]
fun test_stake_zero_fud() {
    let mut world = new_world();

    world.setup_pools();

    world.scenario.next_tx(ALICE); 

    let clock = &world.clock; 

    let alice_account = world.farm.stake(
        clock, 
        mint_for_testing(0, world.scenario.ctx()), 
        0, 
        world.scenario.ctx()
    );

    destroy(alice_account);

    world.end();
}

#[test]
#[expected_failure]
fun test_stake_on_unbound_pool() {
    let mut world = new_world();

    world.setup_pools();

    world.scenario.next_tx(ALICE); 

    let clock = &world.clock; 

    let alice_account = world.farm.stake(
        clock, 
        mint_for_testing(ONE_FUD, world.scenario.ctx()), 
        3, 
        world.scenario.ctx()
    );

    destroy(alice_account);

    world.end();
}

fun setup_pools(world: &mut World) {
    let auth_witness = world.acl.sign_in(&world.admin);

    world.farm.add_pool(&auth_witness, POOL1_REWARD_PER_SECOND, DAY);
    world.farm.add_pool(&auth_witness, POOL2_REWARD_PER_SECOND, DAY * 2);
    world.farm.add_pool(&auth_witness, POOL3_REWARD_PER_SECOND, DAY * 3);

    world.farm.add_rewards(mint_for_testing(100_000 * 10_000, world.scenario.ctx()));
    world.farm.update_start_timestamp(&auth_witness, 0);
}

fun new_world(): World {
    let mut scenario = ts::begin(OWNER);

    let clock = clock::create_for_testing(scenario.ctx());
    
    acl::init_for_testing(scenario.ctx());
    fud_staking::init_for_testing(scenario.ctx());

    scenario.next_tx(OWNER);

    let farm = scenario.take_shared<Farm>();
    let mut acl = scenario.take_shared<ACL>();
    let super_admin = scenario.take_from_sender<SuperAdmin>();
    let admin = acl.new(&super_admin, scenario.ctx());

    World {
        scenario,
        clock,
        farm,
        acl,
        super_admin,
        admin,
    }
}

fun end(world: World) {
    destroy(world);
}

#[test_only]
module fud_staking::fud_staking_tests;

use sui::{
    clock::{Self, Clock},
    test_utils::{assert_eq, destroy},
    test_scenario::{Self as ts, Scenario},
};

use fud_staking::{
    fud_staking::{Self, Farm},
    acl::{Self, SuperAdmin, Admin, ACL},
};

const OWNER: address = @0x0;
const MAX_U64: u64 = 0xFFFFFFFFFFFFFFFF;
const DAY: u64 = 86400;

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

fun setup_pools(world: &mut World) {
    let auth_witness = world.acl.sign_in(&world.admin);

    world.farm.add_pool(&auth_witness, POOL1_REWARD_PER_SECOND, DAY);
    world.farm.add_pool(&auth_witness, POOL2_REWARD_PER_SECOND, DAY * 2);
    world.farm.add_pool(&auth_witness, POOL3_REWARD_PER_SECOND, DAY * 3);
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

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

public struct World {
    clock: Clock,
    farm: Farm,
    acl: ACL,
    admin: Admin,
    scenario: Scenario,
    super_admin: SuperAdmin,
}

#[test]
fun test_stake() {
    let world = new_world(); 

    world.end()
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

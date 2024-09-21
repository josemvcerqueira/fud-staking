module fud_staking::fud_staking;
// === Imports === 

use sui::{
    coin::Coin,
    event::emit,
    clock::Clock,
    balance::{Self, Balance},
};

use fud::fud::FUD;

use fud_staking::acl::AuthWitness;

// === Constants ===  

// @dev Fud has 5 decimals -> 10e5
const FUD_DECIMALS_SCALAR: u256 = 100_000;
const MAX_U64: u64 = 0xFFFFFFFFFFFFFFFF;

// === Errors ===  

#[error]
const OutOfBounds: vector<u8> = b"There is no pool at the specified index";

#[error]
const LockPeriodNotOver: vector<u8> = b"The lock period has not yet passed";

#[error]
const ZeroFudStaked: vector<u8> = b"Cannot stake 0 FUD";

// === Structs === 

public struct Account has key, store {
    id: UID,
    staked: Balance<FUD>, 
    reward_debt: u256,
    initial_time: u64,
    pool_index: u64,
}

public struct Pool has store {
    rewards_per_second: u64,
    last_reward_update: u64,
    accrued_rewards_per_share: u256, 
    total_staked_fud: u64,
    lock_period: u64,
}

public struct Farm has key {
    id: UID,
    start_timestamp: u64,
    fud_rewards: Balance<FUD>, 
    pools: vector<Pool>,
}

// === Events === 

public struct StakeEvent has store, copy, drop {
    account: address,
    amount: u64,
    pool_index: u64,
    initial_time: u64,
}

public struct UnstakeEvent has store, copy, drop {
    amount: u64,
    rewards: u64,
    pool_index: u64,
}

public struct AddRewardsEvent has store, copy, drop {
    amount: u64,
    total_rewards: u64,
}

public struct UpdateRewardsPerSecondEvent has store, copy, drop {
    pool_index: u64,
    rewards_per_second: u64,
}

public struct UpdateLockPeriodEvent has store, copy, drop {
    pool_index: u64,
    lock_period: u64,
}

// === Initializers === 

fun init(ctx: &mut TxContext) {
    let farm = Farm {
        id: object::new(ctx),
        start_timestamp: MAX_U64,
        fud_rewards: balance::zero(),
        pools: vector[]
    };

    transfer::share_object(farm);
}

// === Public Mutative Functions === 

public fun add_rewards(
    farm: &mut Farm,
    rewards: Coin<FUD>,
) {
    emit(AddRewardsEvent {
        amount: rewards.value(),
        total_rewards: farm.fud_rewards.value() + rewards.value()
    });

    farm.fud_rewards.join(rewards.into_balance());
}

public fun stake(
    farm: &mut Farm,
    clock: &Clock,
    stake: Coin<FUD>,
    pool_index: u64,
    ctx: &mut TxContext,
): Account {
    assert!(stake.value() != 0, ZeroFudStaked);
    assert!(farm.pools.length() - 1 >= pool_index, OutOfBounds);

    update(farm, timestamp_s(clock), pool_index);

    let pool = &mut farm.pools[pool_index]; 

    let stake_amount = stake.value();

    pool.total_staked_fud = pool.total_staked_fud + stake_amount;

    let account = Account {
        id: object::new(ctx),
        staked: stake.into_balance(),
        reward_debt: calculate_reward_debt(stake_amount, pool.accrued_rewards_per_share),
        initial_time: timestamp_s(clock),
        pool_index
    };

    emit(StakeEvent {
        account: account.id.to_address(),
        amount: stake_amount,
        pool_index,
        initial_time: timestamp_s(clock)
    });

    account
}

public fun unstake(
    farm: &mut Farm,
    clock: &Clock,
    account: Account,
    ctx: &mut TxContext,
): Coin<FUD> {
    let now = timestamp_s(clock);

    assert!(account.initial_time + farm.pools[account.pool_index].lock_period >= now, LockPeriodNotOver);

    update(farm, now, account.pool_index);

    let pending_reward = calculate_pending_rewards(
        &account,
        farm.pools[account.pool_index].accrued_rewards_per_share,
    );

    let Account { id, staked, pool_index, .. } = account;

    id.delete(); 

    let pool = &mut farm.pools[pool_index];

    pool.total_staked_fud = pool.total_staked_fud - staked.value();

    emit(UnstakeEvent {
        amount: staked.value(),
        rewards: pending_reward,
        pool_index
    });

    let mut total_fud = staked.into_coin(ctx);

    total_fud.join(farm.fud_rewards.split(pending_reward).into_coin(ctx));

    total_fud
}

// === Public View Functions === 

public fun staked(account: &Account):u64 {
    account.staked.value()
}

public fun reward_debt(account: &Account): u256 {
    account.reward_debt
}

public fun initial_time(account: &Account): u64 {
    account.initial_time
}

public fun pool_index(account: &Account): u64 {
    account.pool_index
}

public fun rewards_per_second(farm: &Farm, pool_index: u64): u64 {
    farm.pools[pool_index].rewards_per_second
}

public fun lock_period(farm: &Farm, pool_index: u64): u64 {
    farm.pools[pool_index].lock_period
}

public fun total_staked_fud(farm: &Farm, pool_index: u64): u64 {
    farm.pools[pool_index].total_staked_fud
}

public fun accrued_rewards_per_share(farm: &Farm, pool_index: u64): u256 {
    farm.pools[pool_index].accrued_rewards_per_share
}

public fun last_reward_update(farm: &Farm, pool_index: u64): u64 {
    farm.pools[pool_index].last_reward_update
}

public fun start_timestamp(farm: &Farm): u64 {
    farm.start_timestamp
}

public fun fud_rewards(farm: &Farm): u64 {
    farm.fud_rewards.value()
}

public fun total_pools(farm: &Farm): u64 {
    farm.pools.length()
}

public fun pending_rewards(
    farm: &Farm,
    clock: &Clock,
    account: &Account,
): u64 {
    let now = timestamp_s(clock);

    let pool = &farm.pools[account.pool_index];
    
    let cond = pool.total_staked_fud == 0 || pool.last_reward_update >= now;

    let accrued_rewards_per_share = if (cond) {
        pool.accrued_rewards_per_share
    } else {
        calculate_accrued_rewards_per_share(
            pool.rewards_per_second,
            pool.accrued_rewards_per_share,
            pool.total_staked_fud,
            farm.fud_rewards.value(),
            now - pool.last_reward_update
        )
    };

    calculate_pending_rewards(account, accrued_rewards_per_share)
}

// === Admin Functions === 

public fun add_pool(
    farm: &mut Farm,
    _: &AuthWitness,
    rewards_per_second: u64,
    lock_period: u64
) {
    let pool = Pool {
        rewards_per_second,
        last_reward_update: 0,
        accrued_rewards_per_share: 0,
        total_staked_fud: 0,
        lock_period
    };
    
    farm.pools.push_back(pool);
}

public fun update_rewards_per_second(
    farm: &mut Farm,
    clock: &Clock,
    _: &AuthWitness,
    pool_index: u64,
    rewards_per_second: u64,
) {
    update(farm, timestamp_s(clock), pool_index);

    let pool = &mut farm.pools[pool_index];

    pool.rewards_per_second = rewards_per_second;

    emit(UpdateRewardsPerSecondEvent {
        pool_index,
        rewards_per_second
    });
}

public fun update_lock_period(
    farm: &mut Farm,
    clock: &Clock,
    _: &AuthWitness,
    pool_index: u64,
    lock_period: u64
) {
    update(farm, timestamp_s(clock), pool_index);

    let pool = &mut farm.pools[pool_index];

    pool.lock_period = lock_period;

    emit(UpdateLockPeriodEvent {
        pool_index,
        lock_period
    });
}

// === Private Functions === 

fun timestamp_s(c: &Clock): u64 {
    c.timestamp_ms() / 1000
}

fun update(farm: &mut Farm, now: u64, pool_index: u64) {
    let pool = &mut farm.pools[pool_index];

    if (pool.last_reward_update >= now || farm.start_timestamp > now) return;

    let prev_reward_update = pool.last_reward_update;
    pool.last_reward_update = now;

    if (pool.total_staked_fud == 0) return;

    pool.accrued_rewards_per_share = calculate_accrued_rewards_per_share(
        pool.rewards_per_second,
        pool.accrued_rewards_per_share,
        pool.total_staked_fud,
        farm.fud_rewards.value(),
        now - prev_reward_update
    );
}

fun calculate_accrued_rewards_per_share(
    rewards_per_second: u64,
    last_accrued_rewards_per_share: u256,
    total_staked_token: u64,
    total_reward_value: u64,
    timestamp_delta: u64,
): u256 {
    let (
        total_staked_token,
        total_reward_value,
        rewards_per_second,
        timestamp_delta
    ) = (
        (total_staked_token as u256),
        (total_reward_value as u256),
        (rewards_per_second as u256),
        (timestamp_delta as u256)
    );

    let reward = min_u256(total_reward_value, rewards_per_second * timestamp_delta);

    last_accrued_rewards_per_share + ((reward * FUD_DECIMALS_SCALAR) / total_staked_token)
}

fun calculate_pending_rewards(
    acc: &Account,
    accrued_rewards_per_share: u256,
): u64 {
    (
        (
            ((acc.staked.value() as u256) * accrued_rewards_per_share / FUD_DECIMALS_SCALAR) -
                acc.reward_debt
        ) as u64
    )
}

fun calculate_reward_debt(
    stake_amount: u64,
    accrued_rewards_per_share: u256,
): u256 {
    ((stake_amount as u256) * accrued_rewards_per_share) / FUD_DECIMALS_SCALAR
}

// === Math === 

public fun min(a: u64, b: u64): u64 {
    if (a < b) a else b
}

public fun min_u256(a: u256, b: u256): u256 {
    if (a < b) a else b
}

// === Test Functions === 

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
}
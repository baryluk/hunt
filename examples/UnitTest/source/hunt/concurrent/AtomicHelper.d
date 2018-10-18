module hunt.concurrent.AtomicHelper;

import core.atomic;

class AtomicHelper {
    static void store(T)(ref T stuff, T newVal) {
        core.atomic.atomicStore(*(cast(shared)&stuff), newVal);
    }

    static T load(T)(ref T val) {
        return core.atomic.atomicLoad(*(cast(shared)&val));
    }

    static bool cas(T)(ref T stuff, T testVal, lazy T newVal) {
        return core.atomic.cas(cast(shared)&stuff, cast(shared)testVal, cast(shared)newVal);
    }

    static T increment(T, U)(ref T stuff, U delta = 1) if (__traits(isIntegral, T)) {
        return core.atomic.atomicOp!("+=")(stuff, delta);
    }

    static T decrement(T, U)(ref T stuff, U delta = 1) if (__traits(isIntegral, T)) {
        return core.atomic.atomicOp!("-=")(stuff, delta);
    }

    static T getAndAdd(T, U)(ref T stuff, U delta) {
        T v = stuff;
        increment(stuff, delta);
        return v;
    }

    static T getAndIncrement(T)(ref T stuff) {
        return getAndAdd(stuff, 1);
    }

    static T getAndDecrement(T)(ref T stuff) {
        return getAndAdd(stuff, -1);
    }
}


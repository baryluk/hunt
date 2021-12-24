module hunt.util.ResoureManager;

import hunt.logging;
import hunt.util.Closeable;

import hunt.util.worker.WorkerThread;

import core.memory;
import core.thread;

private Closeable[] _closeableObjects;

void registerResoure(Closeable res) {
    assert(res !is null);
    foreach (Closeable obj; _closeableObjects) {
        if(obj is res) {
            version (HUNT_IO_DEBUG) {
                tracef("%s@%s has been registered... %d", typeid(cast(Object)res), cast(void*)res);
            }
            return;
        }
    }
    _closeableObjects ~= res;
}

void collectResoure() nothrow {
    version (HUNT_IO_DEBUG) {
        tracef("Collecting (remains: %d)...", _closeableObjects.length);
    }

    Closeable[] objects = _closeableObjects;
    _closeableObjects = null;

    foreach (obj; objects) {
        try {
            obj.close();
        } catch (Throwable t) {
            warning(t);
        }
    }

    // GC.collect();
    // GC.minimize();
}

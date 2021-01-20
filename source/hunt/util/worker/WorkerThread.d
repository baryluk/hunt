module hunt.util.worker.WorkerThread;

import hunt.util.Closeable;
import hunt.util.ResoureManager;
import hunt.util.worker.Task;
import hunt.util.worker.Worker;

import hunt.logging.ConsoleLogger;

import core.atomic;
import core.memory;
import core.thread;
import core.sync.condition;
import core.sync.mutex;
import std.conv;



enum WorkerThreadState {
    Idle,
    Busy, // occupied
    Stopped
}

bool inWorkerThread() {
    WorkerThread th = cast(WorkerThread) Thread.getThis();
    return th !is null;
}

/**
 *
 */
class WorkerThread : Thread {

    private shared WorkerThreadState _state;
    private size_t _index;
    private Task _task;
    private Duration _timeout;

    private Condition _condition;
    private Mutex _mutex;

    /* For autonumbering anonymous threads. */
    // private static shared int threadInitNumber = 0;
    // private static int nextThreadNumber() {
    //     return core.atomic.atomicOp!"+="(threadInitNumber, 1);
    // }

    this(size_t index, Duration timeout = 5.seconds, size_t stackSize = 0) {
        _index = index;
        _timeout = timeout;
        _state = WorkerThreadState.Idle;
        _mutex = new Mutex();
        _condition = new Condition(_mutex);
        this.name = "WorkerThread-" ~ _index.to!string();
        super(&run, stackSize);
    }

    void stop() {
        _state = WorkerThreadState.Stopped;
    }

    bool isBusy() {
        return _state == WorkerThreadState.Busy;
    }

    WorkerThreadState state() {
        return _state;
    }

    size_t index() {
        return _index;
    }

    void attatch(Task task) {
        assert(task !is null);
        bool r = cas(&_state, WorkerThreadState.Idle, WorkerThreadState.Busy);

        if (r) {
            version(HUNT_IO_DEBUG) {
                infof("attatching task %d with thread %s", task.id, this.name);
            }

            _mutex.lock();
            scope (exit) {
                _mutex.unlock();
            }
            _task = task;
            _condition.notify();
            
        } else {
            warningf("%s is unavailable. state: %s", this.name(), _state);
        }
    }

    private void run() nothrow {
        while (_state != WorkerThreadState.Stopped) {

            scope (exit) {
                version (HUNT_IO_DEBUG) {
                    tracef("%s Done. state: %s", this.name(), _state);
                }
                collectResoure();
                bool r = cas(&_state, WorkerThreadState.Busy, WorkerThreadState.Idle);
                if(r) {
                    _task = null;
                } else {
                    warning("Failed to set thread %s to Idle, its state is %s", this.name, _state);
                }
            } 

            try {
                doRun();
            } catch (Throwable ex) {
                warning(ex);
            }
        }
        
        version (HUNT_DEBUG) tracef("%s Stopped. state: %s", this.name(), _state);
    }

    private void doRun() {
        version (HUNT_IO_DEBUG){
            tracef("%s waiting in %s ..., state: %s", this.name(), _timeout, _state);
        }
        
        Task task = _task;
        while(task is null && _state != WorkerThreadState.Stopped) {
            _mutex.lock();
            scope (exit) {
                _mutex.unlock();
            }
            bool r = _condition.wait(_timeout);
            if(r) {
                task = _task;
            } else {
                version(HUNT_IO_DEBUG) warningf("No task attatched on thread %s in %s", this.name, _timeout);
            }
        }
       
        if(task !is null) {
            version(HUNT_IO_DEBUG) {
                tracef("Try to exeucte task %d in thread %s, its status: %s", task.id, this.name, task.status);
            }
            task.execute();
        }
    }
}
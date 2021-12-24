module hunt.util.worker.Worker;

import hunt.util.worker.Task;
// import hunt.util.worker.TaskQueue;
import hunt.util.worker.WorkerThread;
import hunt.logging;

import core.atomic;
import core.sync.condition;
import core.sync.mutex;
import core.thread;

import std.conv; 
import std.concurrency;



/**
 * 
 */
class Worker {

    private size_t _size;
    private Thread _masterThread;
    private WorkerThread[] _workerThreads;
    private Task[size_t] _tasks;
    private Mutex _taskLocker;


    private TaskQueue _taskQueue;
    private shared bool _isRunning = false;

    this(TaskQueue taskQueue, size_t size = 8) {
        _taskQueue = taskQueue;
        _size = size;

        version(HUNT_DEBUG) {
            infof("Worker size: %d", size);
        }

        initialize();
    }

    private void initialize() {
        _taskLocker = new Mutex();
        _workerThreads = new WorkerThread[_size];
        
        foreach(size_t index; 0 .. _size) {
            WorkerThread thread = new WorkerThread(index);
            thread.start();

            _workerThreads[index] = thread;
        }
    }

    void inspect() {

        foreach(WorkerThread th; _workerThreads) {
            
            Task task = th.task();

            if(th.state() == WorkerThreadState.Busy) {
                if(task is null) {
                    warning("A dead worker thread detected: %s, %s", th.name, th.state());
                } else {
                    tracef("Thread: %s,  state: %s, lifeTime: %s", th.name, th.state(), task.lifeTime());
                }
            } else {
                if(task is null) {
                    tracef("Thread: %s,  state: %s", th.name, th.state());
                } else {
                    tracef("Thread: %s,  state: %s", th.name, th.state(), task.executionTime);
                }
            }
        }
    }

    void put(Task task) {
        _taskQueue.push(task);

        _taskLocker.lock();
        scope(exit) {
            _taskLocker.unlock();
        }

        _tasks[task.id] = task;
    }

    Task get(size_t id) {
        _taskLocker.lock();
        scope(exit) {
            _taskLocker.unlock();
        } 

        auto itemPtr = id in _tasks;
        if(itemPtr is null) {
            throw new Exception("Task does NOT exist: " ~ id.to!string);
        }

        return *itemPtr;
    }

    void remove(size_t id) {
        _taskLocker.lock();
        scope(exit) {
            _taskLocker.unlock();
        } 

        _tasks.remove(id);
    }

    void clear() {
        _taskLocker.lock();
        scope(exit) {
            _taskLocker.unlock();
        } 
        _tasks.clear();

    }

    void run() {
        bool r = cas(&_isRunning, false, true);
        if(r) {
            _masterThread = new Thread(&doRun);
            _masterThread.start();
        }
    }

    void stop() {
        bool r = cas(&_isRunning, true, false);

        if(r) {
            version(HUNT_IO_DEBUG) {
                info("Stopping all the threads...");
            }


            foreach(size_t index; 0 .. _size) {
                _workerThreads[index].stop();
                _workerThreads[index].join();
            }

            
            // To stop the master thread as soon as possible.
            // _taskQueue.push(null); 
            _taskQueue.clear();

            if(_masterThread !is null) {
                _masterThread.join();
            }

            version(HUNT_IO_DEBUG) {
                info("All the threads stopped.");
            }
        }
    }

    private WorkerThread findIdleThread() {
        foreach(size_t index, WorkerThread thread; _workerThreads) {
            version(HUNT_IO_DEBUG) {
                tracef("Thread: %s, state: %s", thread.name, thread.state);
            }

            if(thread.isIdle())
                return thread;
        }

        return null;
    } 

    private void doRun() {
        while(_isRunning) {
            try {
                version(HUNT_IO_DEBUG) info("running...");
                Task task = _taskQueue.pop();
                if(!_isRunning) break;

                if(task is null) {
                    version(HUNT_IO_DEBUG) {
                        warning("A null task popped!");
                        inspect();
                    }
                    continue;
                }

                WorkerThread workerThread;
                bool isAttatched = false;
                
                do {
                    workerThread = findIdleThread();

                    // All worker threads are busy!
                    if(workerThread is null) {
                        // version(HUNT_METRIC) {
                        //     _taskQueue.inspect();
                        // }
                        // trace("All worker threads are busy!");
                        // Thread.sleep(1.seconds);
                        // Thread.sleep(10.msecs);
                        Thread.yield();
                    } else {
                        isAttatched = workerThread.attatch(task);
                    }
                } while(!isAttatched && _isRunning);

            } catch(Throwable ex) {
                warning(ex);
            }
        }

        version(HUNT_IO_DEBUG) info("Worker stopped!");

    }

}


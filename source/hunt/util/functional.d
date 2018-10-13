module hunt.util.functional;

import std.functional;
import std.traits;
import std.typecons;
import std.typetuple;

// interface BiConsumer(T, U) {

//     /**
//      * Performs this operation on the given arguments.
//      *
//      * @param t the first input argument
//      * @param u the second input argument
//      */
//     void accept(T t, U u);

//     /**
//      * Returns a composed {@code BiConsumer} that performs, in sequence, this
//      * operation followed by the {@code after} operation. If performing either
//      * operation throws an exception, it is relayed to the caller of the
//      * composed operation.  If performing this operation throws an exception,
//      * the {@code after} operation will not be performed.
//      *
//      * @param after the operation to perform after this operation
//      * @return a composed {@code BiConsumer} that performs in sequence this
//      * operation followed by the {@code after} operation
//      * @throws NullPointerException if {@code after} is null
//      */
//     // default BiConsumer<T, U> andThen(BiConsumer<T, U> after) {
//     //     Objects.requireNonNull(after);

//     //     return (l, r) -> {
//     //         accept(l, r);
//     //         after.accept(l, r);
//     //     };
//     // }
// }


// interface BiFunction(T, U, R) {

//     /**
//      * Applies this function to the given arguments.
//      *
//      * @param t the first function argument
//      * @param u the second function argument
//      * @return the function result
//      */
//     R apply(T t, U u);

//     /**
//      * Returns a composed function that first applies this function to
//      * its input, and then applies the {@code after} function to the result.
//      * If evaluation of either function throws an exception, it is relayed to
//      * the caller of the composed function.
//      *
//      * @param <V> the type of output of the {@code after} function, and of the
//      *           composed function
//      * @param after the function to apply after this function is applied
//      * @return a composed function that first applies this function and then
//      * applies the {@code after} function
//      * @throws NullPointerException if after is null
//      */
//     // default <V> BiFunction<T, U, V> andThen(Function<R, V> after) {
//     //     Objects.requireNonNull(after);
//     //     return (T t, U u) -> after.apply(apply(t, u));
//     // }
// }


  
/**
 * <p>
 * A callback abstraction that handles completed/failed events of asynchronous
 * operations.
 * </p>
 * <p>
 * <p>
 * Semantically this is equivalent to an optimise Promise&lt;Void&gt;, but
 * callback is a more meaningful name than EmptyPromise
 * </p>
 */
interface Callback {
    /**
     * Instance of Adapter that can be used when the callback methods need an
     * empty implementation without incurring in the cost of allocating a new
     * Adapter object.
     */
    __gshared Callback NOOP;

    shared static this()
    {
        NOOP = new NoopCallback();
    }

    /**
     * <p>
     * Callback invoked when the operation completes.
     * </p>
     *
     * @see #failed(Throwable)
     */
    void succeeded();

    /**
     * <p>
     * Callback invoked when the operation fails.
     * </p>
     *
     * @param x the reason for the operation failure
     */
    void failed(Exception x);

    /**
     * @return True if the callback is known to never block the caller
     */
    bool isNonBlocking();
}


/**
*/
class NestedCallback : Callback {
        private Callback callback;

        this(Callback callback) {
            this.callback = callback;
        }

        this(NestedCallback nested) {
            this.callback = nested.callback;
        }

        Callback getCallback() {
            return callback;
        }
        
        void succeeded() {
            callback.succeeded();
        }
        
        void failed(Exception x) {
            callback.failed(x);
        }

        bool isNonBlocking() {
            return callback.isNonBlocking();
        }
    }

/**
 * <p>
 * A callback abstraction that handles completed/failed events of asynchronous
 * operations.
 * </p>
 * <p>
 * <p>
 * Semantically this is equivalent to an optimise Promise&lt;Void&gt;, but
 * callback is a more meaningful name than EmptyPromise
 * </p>
 */
class NoopCallback : Callback {
    /**
     * <p>
     * Callback invoked when the operation completes.
     * </p>
     *
     * @see #failed(Throwable)
     */
    void succeeded() {
    }

    /**
     * <p>
     * Callback invoked when the operation fails.
     * </p>
     *
     * @param x the reason for the operation failure
     */
    void failed(Exception x) {
    }

    /**
     * @return True if the callback is known to never block the caller
     */
    bool isNonBlocking() {
        return false;
    }
}


pragma(inline) auto bind(T, Args...)(T fun, Args args) if (isCallable!(T))
{
    alias FUNTYPE = Parameters!(fun);
    static if (is(Args == void))
    {
        static if (isDelegate!T)
            return fun;
        else
            return toDelegate(fun);
    }
    else static if (FUNTYPE.length > args.length)
    {
        alias DTYPE = FUNTYPE[args.length .. $];
        return delegate(DTYPE ars) {
            TypeTuple!(FUNTYPE) value;
            value[0 .. args.length] = args[];
            value[args.length .. $] = ars[];
            return fun(value);
        };
    }
    else
    {
        return delegate() { return fun(args); };
    }
}

unittest
{

    import std.stdio;
    import core.thread;

    class AA
    {
        void show(int i)
        {
            writeln("i = ", i); // the value is not(0,1,2,3), it all is 2.
        }

        void show(int i, int b)
        {
            b += i * 10;
            writeln("b = ", b); // the value is not(0,1,2,3), it all is 2.
        }

        void aa()
        {
            writeln("aaaaaaaa ");
        }

        void dshow(int i, string str, double t)
        {
            writeln("i = ", i, "   str = ", str, "   t = ", t);
        }
    }

    void listRun(int i)
    {
        writeln("i = ", i);
    }

    void listRun2(int i, int b)
    {
        writeln("i = ", i, "  b = ", b);
    }

    void list()
    {
        writeln("bbbbbbbbbbbb");
    }

    void dooo(Thread[] t1, Thread[] t2, AA a)
    {
        foreach (i; 0 .. 4)
        {
            auto th = new Thread(bind!(void delegate(int, int))(&a.show, i, i));
            t1[i] = th;
            auto th2 = new Thread(bind(&listRun, (i + 10)));
            t2[i] = th2;
        }
    }

    //  void main()
    {
        auto tdel = bind(&listRun);
        tdel(9);
        bind(&listRun2, 4)(5);
        bind(&listRun2, 40, 50)();

        AA a = new AA();
        bind(&a.dshow, 5, "hahah")(20.05);

        Thread[4] _thread;
        Thread[4] _thread2;
        // AA a = new AA();

        dooo(_thread, _thread2, a);

        foreach (i; 0 .. 4)
        {
            _thread[i].start();
        }

        foreach (i; 0 .. 4)
        {
            _thread2[i].start();
        }

    }
}

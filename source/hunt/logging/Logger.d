/*
 * Hunt - A refined core library for D programming language.
 *
 * Copyright (C) 2018-2019 HuntLabs
 *
 * Website: https://www.huntlabs.net/
 *
 * Licensed under the Apache-2.0 License.
 *
 */
module hunt.logging.Logger;

// import hunt.util.ThreadHelper;

import hunt.util.ThreadHelper;

import core.thread;

import std.algorithm.iteration;
import std.array;
import std.concurrency;
import std.exception;
import std.file;
import std.parallelism;
import std.stdio;
import std.datetime;
import std.format;
import std.range;
import std.conv;
import std.regex;
import std.path;
import std.typecons;
import std.traits;
import std.string;

alias LogLayoutHandler = string delegate(string time_prior, string tid, string level, string myFunc, 
				string msg, string file, size_t line);

private:

__gshared LogLayoutHandler _layoutHandler;

LogLayoutHandler layoutHandler() {
	if(_layoutHandler is null) {
		_layoutHandler = (string time_prior, string tid, string level, string myFunc, 
				string msg, string file, size_t line) {
			import std.format;
			return format("%s | %s | %s | %s | %s | %s:%d", time_prior, tid, level, myFunc, msg, file, line);
			//return time_prior ~ " (" ~ tid ~ ") [" ~ level ~ "] " ~ myFunc ~
			//	" - " ~ msg ~ " - " ~ file ~ ":" ~ to!string(line);
		};
	}

	return _layoutHandler;
}

class SizeBaseRollover
{

	import std.path;
	import std.string;
	import std.typecons;

	string path;
	string dir;
	string baseName;
	string ext;
	string activeFilePath;

	/**
	 * Max size of one file
	 */
	uint maxSize;

	/**
	 * Max number of working files
	 */
	uint maxHistory;

	this(string fileName, string size, uint maxNum)
	{
		path = fileName;
		auto fileInfo = parseConfigFilePath(fileName);
		dir = fileInfo[0];
		baseName = fileInfo[1];
		ext = fileInfo[2];

		activeFilePath = path;
		maxSize = extractSize(size);

		maxHistory = maxNum;
	}

	auto parseConfigFilePath(string rawConfigFile)
	{
		string configFile = buildNormalizedPath(rawConfigFile);

		immutable dir = configFile.dirName;
		string fullBaseName = std.path.baseName(configFile);
		auto ldotPos = fullBaseName.lastIndexOf(".");
		immutable ext = (ldotPos > 0) ? fullBaseName[ldotPos + 1 .. $] : "log";
		immutable baseName = (ldotPos > 0) ? fullBaseName[0 .. ldotPos] : fullBaseName;

		return tuple(dir, baseName, ext);
	}

	uint extractSize(string size)
	{
		import std.uni : toLower;
		import std.uni : toUpper;
		import std.conv;

		uint nsize = 0;
		auto n = matchAll(size, regex(`\d*`));
		if (!n.empty && (n.hit.length != 0))
		{
			nsize = to!int(n.hit);
			auto m = matchAll(size, regex(`\D{1}`));
			if (!m.empty && (m.hit.length != 0))
			{
				switch (m.hit.toUpper)
				{
				case "K":
					nsize *= KB;
					break;
				case "M":
					nsize *= MB;
					break;
				case "G":
					nsize *= GB;
					break;
				case "T":
					nsize *= TB;
					break;
				case "P":
					nsize *= PB;
					break;
				default:
					throw new Exception("In Logger configuration uncorrect number: " ~ size);
				}
			}
		}
		return nsize;
	}

	enum KB = 1024;
	enum MB = KB * 1024;
	enum GB = MB * 1024;
	enum TB = GB * 1024;
	enum PB = TB * 1024;

	/**
	 * Scan work directory
	 * save needed files to pool
 	 */
	string[] scanDir()
	{
		import std.algorithm.sorting : sort;
		import std.algorithm;

		bool tc(string s)
		{
			static import std.path;

			auto base = std.path.baseName(s);
			auto m = matchAll(base, regex(baseName ~ `\d*\.` ~ ext));
			if (m.empty || (m.hit != base))
			{
				return false;
			}
			return true;
		}

		return std.file.dirEntries(dir, SpanMode.shallow)
			.filter!(a => a.isFile).map!(a => a.name).filter!(a => tc(a))
			.array.sort!("a < b").array;
	}

	/**
	 * Do files rolling by size
	 */

	bool roll(string msg)
	{
		auto filePool = scanDir();
		if (filePool.length == 0)
		{
			return false;
		}
		if ((getSize(filePool[0]) + msg.length) >= maxSize)
		{
			//if ((filePool.front.getSize == 0) throw
			if (filePool.length >= maxHistory)
			{
				std.file.remove(filePool[$ - 1]);
				filePool = filePool[0 .. $ - 1];
			}
			//carry(filePool);
			return true;
		}
		return false;
	}

	/**
	 * Rename log files
	 */

	void carry()
	{
		import std.conv;
		import std.path;

		auto filePool = scanDir();
		foreach_reverse (ref file; filePool)
		{
			auto newFile = dir ~ dirSeparator ~ baseName ~ to!string(extractNum(file) + 1)
				~ "." ~ ext;
			std.file.rename(file, newFile);
			file = newFile;
		}
	}

	/**
	 * Extract number from file name
	 */
	uint extractNum(string file)
	{
		import std.conv;

		uint num = 0;
		try
		{
			static import std.path;
			import std.string;

			auto fch = std.path.baseName(file).chompPrefix(baseName);
			auto m = matchAll(fch, regex(`\d*`));

			if (!m.empty && m.hit.length > 0)
			{
				num = to!uint(m.hit);
			}
		}
		catch (Exception e)
		{
			throw new Exception("Uncorrect log file name: " ~ file ~ "  -> " ~ e.msg);
		}
		return num;
	}

}

__gshared Logger g_logger = null;

version (Windows)
{
	import core.sys.windows.wincon;
	import core.sys.windows.winbase;
	import core.sys.windows.windef;

	private __gshared HANDLE g_hout;
	shared static this() {
		g_hout = GetStdHandle(STD_OUTPUT_HANDLE);
	}
}


string code(string func, LogLevel level, bool f = false)()
{
	return "void " ~ func
		~ `(string file = __FILE__ , size_t line = __LINE__ , string func = __FUNCTION__ , A ...)(lazy A args) nothrow
	{

		if(g_logger is null) {
			Logger.writeFormatColor(`
		~ level.stringof ~ ` , Logger.toFormat(func , Logger.logFormat` ~ (f
				? "f" : "") ~ `(args) , file , line , ` ~ level.stringof ~ `));
		} else {
			g_logger.doWrite(`
		~ level.stringof ~ ` , Logger.toFormat(func , Logger.logFormat` ~ (f
				? "f" : "") ~ `(args) , file , line ,` ~ level.stringof ~ `));
		}
	}`;
}



public:

/**
 * 
 */
class Logger
{
	private LogLayoutHandler _layoutHandler;
	private bool _isRunning = true;
	private __gshared LogLevel g_logLevel = LogLevel.LOG_DEBUG;
	__gshared Logger[string] g_logger;
	static Logger createLogger(string name , LogConf conf)
	{
		g_logger[name] = new Logger(conf);
		return g_logger[name];
	}

	static Logger getLogger(string name)
	{
		return g_logger[name];
	}

	static void setLogLevel(LogLevel level) {
        g_logLevel = level;
    }

	this(LogConf conf, LogLayoutHandler handler = null)
	{
		_layoutHandler = handler;
		_conf = conf;
		string fileName = conf.fileName;

		if (!fileName.empty)
		{
			if(exists(fileName) && isDir(fileName))
				throw new Exception("A direction has existed with the same name.");
			
			createPath(conf.fileName);
			_file = File(conf.fileName, "a");
			_rollover = new SizeBaseRollover(conf.fileName, _conf.maxSize, _conf.maxNum);
		}

		immutable void* data = cast(immutable void*) this;
		if(!_conf.fileName.empty)
			_tid = spawn(&Logger.worker, data);
	}

	void logLayoutHandler(LogLayoutHandler handler) {
		_layoutHandler = handler;
	}

	LogConf conf() {
		return _conf;
	}

	void stop() {
		_isRunning = false;
	}

	bool isRunning() {
		return _isRunning;
	}

	void log(string file = __FILE__ , size_t line = __LINE__ , string func = __FUNCTION__ , A ...)(LogLevel level , lazy A args)
	{
		doWrite(level , toFormat(func , logFormat(args) , file , line , level, _layoutHandler));
	}

	void logf(string file = __FILE__ , size_t line = __LINE__ , string func = __FUNCTION__ , A ...)(LogLevel level , lazy A args)
	{
		doWrite(level , toFormat(func , logFormatf(args) , file , line , level, _layoutHandler));
	}

	void trace(string file = __FILE__ , size_t line = __LINE__ , string func = __FUNCTION__ , A ...)(lazy A args)
	{
		enum LogLevel level = LogLevel.LOG_DEBUG;
		doWrite(level, toFormat(func , logFormat(args) , file , line , level, _layoutHandler));
	}

	void tracef(string file = __FILE__ , size_t line = __LINE__ , string func = __FUNCTION__ , A ...)(lazy A args)
	{
		enum LogLevel level = LogLevel.LOG_DEBUG;
		doWrite(level , toFormat(func , logFormatf(args) , file , line , level, _layoutHandler));
	}

	void info(string file = __FILE__ , size_t line = __LINE__ , string func = __FUNCTION__ , A ...)(lazy A args)
	{
		enum LogLevel level = LogLevel.LOG_INFO;
		doWrite(level, toFormat(func , logFormat(args) , file , line , level, _layoutHandler));
	}

	void infof(string file = __FILE__ , size_t line = __LINE__ , string func = __FUNCTION__ , A ...)(lazy A args)
	{
		enum LogLevel level = LogLevel.LOG_INFO;
		doWrite(level , toFormat(func , logFormatf(args) , file , line , level, _layoutHandler));
	}

	void warning(string file = __FILE__ , size_t line = __LINE__ , string func = __FUNCTION__ , A ...)(lazy A args)
	{
		enum LogLevel level = LogLevel.LOG_WARNING;
		doWrite(level, toFormat(func , logFormat(args) , file , line , level, _layoutHandler));
	}

	void warningf(string file = __FILE__ , size_t line = __LINE__ , string func = __FUNCTION__ , A ...)(lazy A args)
	{
		enum LogLevel level = LogLevel.LOG_WARNING;
		doWrite(level , toFormat(func , logFormatf(args) , file , line , level, _layoutHandler));
	}

	void error(string file = __FILE__ , size_t line = __LINE__ , string func = __FUNCTION__ , A ...)(lazy A args)
	{
		enum LogLevel level = LogLevel.LOG_ERROR;
		doWrite(level, toFormat(func , logFormat(args) , file , line , level, _layoutHandler));
	}

	void errorf(string file = __FILE__ , size_t line = __LINE__ , string func = __FUNCTION__ , A ...)(lazy A args)
	{
		enum LogLevel level = LogLevel.LOG_ERROR;
		doWrite(level , toFormat(func , logFormatf(args) , file , line , level, _layoutHandler));
	}

	void critical(string file = __FILE__ , size_t line = __LINE__ , string func = __FUNCTION__ , A ...)(lazy A args)
	{
		enum LogLevel level = LogLevel.LOG_FATAL;
		doWrite(level, toFormat(func , logFormat(args) , file , line , level, _layoutHandler));
	}

	void criticalf(string file = __FILE__ , size_t line = __LINE__ , string func = __FUNCTION__ , A ...)(lazy A args)
	{
		enum LogLevel level = LogLevel.LOG_FATAL;
		doWrite(level , toFormat(func , logFormatf(args) , file , line , level, _layoutHandler));
	}

	void doWrite(LogLevel level, lazy string msg) nothrow
	{
		if (level >= _conf.level)
		{
			//#1 console 
			//check if enableConsole or appender == AppenderConsole

			if (_conf.fileName == "" || !_conf.disableConsole)
			{
				writeFormatColor(level, msg);
			}

			//#2 file
			if (_conf.fileName != "")
			{
				try
                    send(_tid, msg);
                catch (Exception ex) {
					version(Posix) {
						collectException( {
							write(PRINT_COLOR_RED); 
							write(ex); 
							writeln(PRINT_COLOR_NONE); 
						}());
					} else {
						collectException( {
                        write(ex); 
                    }());
					}
                }
			}
		}
	}



protected:

	static void worker(immutable void* ptr)
	{
		import std.stdio;
		Logger logger = cast(Logger) ptr;
		while (logger !is null && logger.isRunning())
		{
			receive((string msg) {
				logger.saveMsg(msg);
			}, (OwnerTerminated e) { 
				version(HUNT_DEBUG_MORE) {
					logger.saveMsg("Logger OwnerTerminated");
				}
			}, (Variant any) {
				logger.saveMsg("Unknown data type");
			  });
		}
	}

	void saveMsg(string msg)
	{
		try
		{

			if (!_file.name.exists)
			{
				_file = File(_rollover.activeFilePath, "w");
			}
			else if (_rollover.roll(msg))
			{
				_file.detach();
				_rollover.carry();
				_file = File(_rollover.activeFilePath, "w");
			}
			else if (!_file.isOpen())
			{
				_file.open("a");
			}
			_file.writeln(msg);
			_file.flush();

		}
		catch (Throwable e)
		{
			writeln(e.toString());
		}

	}

	static void createPath(string fileFullName)
	{
		import std.path : dirName;
		import std.file : mkdirRecurse;
		import std.file : exists;

		string dir = dirName(fileFullName);
		if (!exists(dir))
			mkdirRecurse(dir);
	}

	static string toString(LogLevel level) nothrow
	{
		string l;
		final switch (level) with (LogLevel)
		{
		case LOG_DEBUG:
			l = "debug";
			break;
		case LOG_INFO:
			l = "info";
			break;
		case LOG_WARNING:
			l = "warning";
			break;
		case LOG_ERROR:
			l = "error";
			break;
		case LOG_FATAL:
			l = "fatal";
			break;
		case LOG_Off:
			l = "off";
			break;
		}
		return l;
	}

	static string logFormatf(A...)(A args)
	{
		auto strings = appender!string();
		formattedWrite(strings, args);
		return strings.data;
	}

	static string logFormat(A...)(A args)
	{
		auto w = appender!string();
		foreach (arg; args)
		{
			alias A = typeof(arg);
			static if (isAggregateType!A || is(A == enum))
			{
				import std.format : formattedWrite;

				formattedWrite(w, "%s", arg);
			}
			else static if (isSomeString!A)
			{
				put(w, arg);
			}
			else static if (isIntegral!A)
			{
				import std.conv : toTextRange;

				toTextRange(arg, w);
			}
			else static if (isBoolean!A)
			{
				put(w, arg ? "true" : "false");
			}
			else static if (isSomeChar!A)
			{
				put(w, arg);
			}
			else
			{
				import std.format : formattedWrite;

				// Most general case
				formattedWrite(w, "%s", arg);
			}
		}
		return w.data;
	}

	static string toFormat(string func, string msg, string file, size_t line, 
			LogLevel level, LogLayoutHandler handler= null)
	{
		import hunt.util.DateTime;
		string time_prior = date("Y-m-d H:i:s");

		string tid = to!string(getTid());

		string[] funcs = func.split(".");
		string myFunc;
		if (funcs.length > 0)
			myFunc = funcs[$ - 1];
		else
			myFunc = func;
		if(handler is null)
			handler = layoutHandler();
		if(handler !is null) {
			return handler(time_prior, tid, toString(level), myFunc, msg, file, line);
		} else {
			/*return time_prior ~ " (" ~ tid ~ ") [" ~ toString(
					level) ~ "] " ~ myFunc ~ " - " ~ msg ~ " - " ~ file ~ ":" ~ to!string(line);*/
			import std.format;
			return format("%s | %s | %s | %s | %s | %s:%d", time_prior, tid, level, myFunc, msg, file, line);
		}
	}

protected:

	LogConf _conf;
	Tid _tid;
	File _file;
	SizeBaseRollover _rollover;
	version (Posix)
	{
		enum PRINT_COLOR_NONE = "\033[m";
		enum PRINT_COLOR_RED = "\033[0;32;31m";
		enum PRINT_COLOR_GREEN = "\033[0;32;32m";
		enum PRINT_COLOR_YELLOW = "\033[1;33m";
	}

	static void writeFormatColor(LogLevel level, lazy string msg) nothrow {
        if (level < g_logLevel)
            return;

        version (Posix) {
            version (Android) {
                string prior_color;
                android_LogPriority logPrioity = android_LogPriority.ANDROID_LOG_INFO;
                switch (level) with (LogLevel) {
                case LOG_ERROR:
                case LOG_FATAL:
                    prior_color = PRINT_COLOR_RED;
                    logPrioity = android_LogPriority.ANDROID_LOG_ERROR;
                    break;
                case LOG_WARNING:
                    prior_color = PRINT_COLOR_YELLOW;
                    logPrioity = android_LogPriority.ANDROID_LOG_WARN;
                    break;
                case LOG_INFO:
                    prior_color = PRINT_COLOR_GREEN;
                    break;
                default:
                    prior_color = string.init;
                }

                try {
                    __android_log_write(logPrioity,
                            LOG_TAG, toStringz(prior_color ~ msg ~ PRINT_COLOR_NONE));
                } catch(Exception ex) {
                    collectException( {
                        write(PRINT_COLOR_RED); 
                        write(ex); 
                        writeln(PRINT_COLOR_NONE); 
                    }());
                }

            } else {
                string prior_color;
                switch (level) with (LogLevel) {
                case LOG_ERROR:
                case LOG_FATAL:
                    prior_color = PRINT_COLOR_RED;
                    break;
                case LOG_WARNING:
                    prior_color = PRINT_COLOR_YELLOW;
                    break;
                case LOG_INFO:
                    prior_color = PRINT_COLOR_GREEN;
                    break;
                default:
                    prior_color = string.init;
                }
                try {
                    writeln(prior_color ~ msg ~ PRINT_COLOR_NONE);
                } catch(Exception ex) {
                    collectException( {
                        write(PRINT_COLOR_RED); 
                        write(ex); 
                        writeln(PRINT_COLOR_NONE); 
                    }());
                }
            }

        } else version (Windows) {
			import hunt.system.WindowsHelper;
            enum defaultColor = FOREGROUND_GREEN | FOREGROUND_RED | FOREGROUND_BLUE;

            ushort color;
            switch (level) with (LogLevel) {
            case LOG_ERROR:
            case LOG_FATAL:
                color = FOREGROUND_RED;
                break;
            case LOG_WARNING:
                color = FOREGROUND_GREEN | FOREGROUND_RED;
                break;
            case LOG_INFO:
                color = FOREGROUND_GREEN;
                break;
            default:
                color = defaultColor;
            }

            ConsoleHelper.writeWithAttribute(msg, color);
        } else {
            assert(false, "Unsupported OS.");
        }
    }
}

enum LogLevel
{
	LOG_DEBUG = 0,
	LOG_INFO = 1,	
	LOG_WARNING = 2,
	LOG_ERROR = 3,
	LOG_FATAL = 4,
	LOG_Off = 5
}

struct LogConf
{
	LogLevel level; // 0 debug 1 info 2 warning 3 error 4 fatal
	bool disableConsole;
	string fileName = "";
	string maxSize = "2MB";
	uint maxNum = 5;
}

void logLoadConf(LogConf conf)
{
	g_logger = new Logger(conf);	
}

void setLogLayout(LogLayoutHandler handler) {
	_layoutHandler = handler;
}

mixin(code!("logDebug", LogLevel.LOG_DEBUG));
mixin(code!("logDebugf", LogLevel.LOG_DEBUG, true));
mixin(code!("logInfo", LogLevel.LOG_INFO));
mixin(code!("logInfof", LogLevel.LOG_INFO, true));
mixin(code!("logWarning", LogLevel.LOG_WARNING));
mixin(code!("logWarningf", LogLevel.LOG_WARNING, true));
mixin(code!("logError", LogLevel.LOG_ERROR));
mixin(code!("logErrorf", LogLevel.LOG_ERROR, true));
mixin(code!("logFatal", LogLevel.LOG_FATAL));
mixin(code!("logFatalf", LogLevel.LOG_FATAL, true));

alias trace = logDebug;
alias tracef = logDebugf;
alias info = logInfo;
alias infof = logInfof;
alias warning = logWarning;
alias warningf = logWarningf;
alias error = logError;
alias errorf = logErrorf;
alias critical = logFatal;
alias criticalf = logFatalf;




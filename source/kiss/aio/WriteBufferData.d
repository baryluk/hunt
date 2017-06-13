



module kiss.aio.WriteBufferData;
import kiss.aio.CompletionHandle;
import kiss.aio.ByteBuffer;


class WriteBufferData {
    WriteCompletionHandle handle;
    void* attachment;
    ByteBuffer buffer;
	WriteBufferData _next;
}

class WriteBufferDataQueue
{
	WriteBufferData  front() nothrow{
		return _frist;
	}

	bool empty() nothrow{
		return _frist is null;
	}

	void enQueue(WriteBufferData wsite) nothrow
	in{
		assert(wsite);
	}body{
		if(_last){
			_last._next = wsite;
		} else {
			_frist = wsite;
		}
		wsite._next = null;
		_last = wsite;
	}

	WriteBufferData deQueue() nothrow
	in{
		assert(_frist && _last);
	}body{
		WriteBufferData  wsite = _frist;
		_frist = _frist._next;
		if(_frist is null)
			_last = null;
		return wsite;
	}

private:
	WriteBufferData  _last = null;
	WriteBufferData  _frist = null;
}




using System;

namespace CodeManager;

public sealed partial class Manager
{
    // Only the synchronous UI application is a batch; never hold this flag
    // across an await where hooks or user interaction can update other slots.
    private void ApplySessionBatch(Func<bool> apply)
    {
        bool nested=_processingStatusBatch,extra=false;
        _processingStatusBatch=true;
        try {extra=apply();}
        finally {_processingStatusBatch=nested;}
        if(extra)_statusBatchDirty=true;
        if(nested || !_statusBatchDirty || !Save())return;
        Dock.UpdateSummary();_statusBatchDirty=false;
        if(_statusBatchNotices!=null) {
            foreach(var notice in _statusBatchNotices)if(notice.Value.Id==notice.Key && notice.Value.Unread)NotifyStatus(notice.Value);
            _statusBatchNotices.Clear();
        }
    }
}

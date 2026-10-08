"""24 compact features; exact formula also implemented in Swift on watchOS."""
import numpy as np

NAMES = ['mag_mean','mag_std','mag_p10','mag_p50','mag_p90','mag_range','mag_abs_dev','mag_rms',
         'diff_abs_mean','diff_std','acf1','acf10','acf20','acf40','peak_hz','power_low','power_walk',
         'power_high','spectral_entropy','mean_vector_norm','axis_std_total','axis_std_min','axis_std_max','mag_skew']

def extract_batch(x):
    """x: (windows,200,3), gravity-including raw accelerometer units g."""
    x = np.asarray(x, dtype=np.float64)
    assert x.ndim == 3 and x.shape[1:] == (200,3)
    m = np.linalg.norm(x,axis=2)
    mean=m.mean(axis=1); centered=m-mean[:,None]; std=m.std(axis=1)
    q=np.quantile(m,[.1,.5,.9],axis=1)
    diff=np.diff(m,axis=1); energy=(centered*centered).sum(axis=1)
    acf=[np.divide((centered[:,:-lag]*centered[:,lag:]).sum(axis=1),energy,
                   out=np.zeros(len(x)),where=energy>1e-12) for lag in [1,10,20,40]]
    powers=np.abs(np.fft.rfft(centered,axis=1))**2
    powers=powers[:,1:81]; freq=np.arange(1,81)/10
    total=powers.sum(axis=1)
    normalized=np.divide(powers,total[:,None],out=np.zeros_like(powers),where=total[:,None]>1e-12)
    entropy=-(normalized*np.log(np.maximum(normalized,1e-30))).sum(axis=1)
    peak=np.where(total>1e-12,freq[powers.argmax(axis=1)],0)
    bands=[normalized[:,(freq>=lo)&(freq<hi)].sum(axis=1) for lo,hi in [(.2,.8),(.8,3),(3,8.01)]]
    axis=x.std(axis=1)
    skew=np.divide((centered**3).mean(axis=1),std**3,out=np.zeros(len(x)),where=std>1e-6)
    result=np.column_stack([mean,std,*q,m.max(axis=1)-m.min(axis=1),np.abs(centered).mean(axis=1),
               np.sqrt((m*m).mean(axis=1)),np.abs(diff).mean(axis=1),diff.std(axis=1),*acf,peak,*bands,
               entropy,np.linalg.norm(x.mean(axis=1),axis=1),np.linalg.norm(axis,axis=1),
               axis.min(axis=1),axis.max(axis=1),skew])
    assert result.shape[1]==len(NAMES) and np.isfinite(result).all()
    return result

import logging
import os
import threading
import time

class AbstractDispatchQueue(object):
  """Facilitates running a function on another thread.

  Clients invoke dispatch_async() to run a function on the thread that pulls from this queue.

  Owning threads invoke run_jobs() periodically.
  """
  def __init__(self):
    self.queue = []
    self.cond = threading.Condition()

  def dispatch_async(self, f):
    self.cond.acquire()
    self.queue.append(f)
    self.notify()
    self.cond.release()

  def run_jobs(self):
    n = 0
    job = self._dequeue()
    while job is not None:
      job()
      job = self._dequeue()
      n += 1
    return n

  def _run_jobs_locked(self):
    n = 0
    job = self._dequeue_locked()
    while job is not None:
      self.cond.release()
      job()
      n += 1
      self.cond.acquire()
      job = self._dequeue_locked()
    return n

  def _dequeue(self):
    self.cond.acquire()
    job = self._dequeue_locked()
    self.cond.release()
    return job

  def _dequeue_locked(self):
    job = None
    if len(self.queue) > 0:
      job = self.queue[0]
      del self.queue[0]
    return job

class IODispatchQueue(AbstractDispatchQueue):
  """A dispatch queue owned by a select loop.

  The select loop should select on self.read_pipe, which becomes readable when run_jobs has works to do.
  """
  def __init__(self):
    AbstractDispatchQueue.__init__(self)
    self.read_pipe, self.write_pipe = os.pipe()

  def run_jobs(self):
    n = AbstractDispatchQueue.run_jobs(self)
    os.read(self.read_pipe, n)

  def notify(self):
    os.write(self.write_pipe, " ")

class IdleDispatchQueue(AbstractDispatchQueue):
  """A condition variable-based dispatch queue that adds the ability to wait
  for a set period of time and notify the condition variable.

  Adds a wait API that blocks until there is work to do.
  """
  def notify(self):
    self.cond.notify_all()

  def wait(self, timeout=None):
    """Waits until there is work to do.

    timeout: If None, wait indefinitely. Otherwise, don't block for more than this many seconds.

    Returns the number of jobs run.
    """
    start_time = time.time()
    n = 0
    if timeout is None:
      self.cond.acquire()
      c = self._run_jobs_locked()
      n += c
      while c == 0:
        self.cond.wait()
        c = self._run_jobs_locked()
        n += c
      self.cond.release()
    else:
      end_time = start_time + timeout
      now = time.time()
      self.cond.acquire()
      while True:
        n = self._run_jobs_locked()
        if n == 0 and now < end_time:
          self.cond.wait(timeout=end_time - now)
        now = time.time()
        if n > 0 or now >= end_time:
          break;
      self.cond.release()
    return n


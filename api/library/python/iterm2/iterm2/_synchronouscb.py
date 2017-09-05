import logging
import threading

class SynchronousCallback(object):
  """A wrapper around a condition variable.

  Contains one bit of state, self.response.
  """
  def __init__(self):
    self.cond = threading.Condition()
    self.response = None

  def callback(self, r):
    """Like notfiying a condition variable, but also sets the response to r."""
    logging.debug("Callback invoked")
    self.cond.acquire()
    self.response = r
    self.cond.notify_all()
    self.cond.release()

  def wait(self):
    """Blocks until there is a response."""
    logging.debug("Waiting for callback to be invoked")
    self.cond.acquire()
    while self.response is None:
      self.cond.wait()
    logging.debug("Callback was invoked")
    self.cond.release()



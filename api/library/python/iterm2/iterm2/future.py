import logging
import _synchronouscb as synchronouscb

"""0-argument callbacks that get invoked just before blocking."""
_idle_observers = []

def add_idle_observer(observer):
  """Adds an idle observer callback. Will be run just before blocking the main thread."""
  _idle_observers.append(observer)

class Future(synchronouscb.SynchronousCallback):
  """Represents a value that will become available later.

  As this is a subclass of SynchronousCallback, invoke callback() when the
  future is resolved. Clients call get() when they're ready to block for a
  value.

  Also has some bells and whistles. When you create a future you can define a
  transform function that will modify the value.

  You can add a "watch" function that gets called asynchronously when the value
  becomes available.
  """

  def __init__(self, transform=None):
    """Initializes a new future.

    transform: If not None, the transform function runs immediately when the
      value becomes available. It takes one argument, the original response. It
      returns a transformed response, which is returned by get().
    """
    synchronouscb.SynchronousCallback.__init__(self)
    if transform is None:
      self.transform = lambda x: x
    else:
      self.transform = transform
    self.transformed_response = None
    self.watches = []

  def get(self):
    """Returns the existing transformed response if available. Otherwise, waits
    until it is available and then returns it."""
    if self.transformed_response is None:
      logging.debug("Waiting on future")
      self.wait()
      logging.debug("REALIZING %s" % str(self))
      self.transformed_response = self.transform(self.response)
      assert self.transformed_response is not None
      self._invoke_watches(self.transformed_response)
    return self.transformed_response

  def watch(self, callback):
    """Adds a watch callback to the future.

    The callback will be invoked when the transformed response becomes available.
    """
    if self.watches is not None:
      logging.debug("Add watch to %s", str(self))
      self.watches.append(callback)
    else:
      logging.debug("Immediately run callback for watch for %s" % str(self))
      callback(self.get())

  def wait(self):
    """Blocks until a value is available.

    Has the side effect of telling idle observers that we're about to block.
    """
    self.idle_spin()
    synchronouscb.SynchronousCallback.wait(self)

  def idle_spin(self):
    """Call this before blocking while idle in the main thread."""
    logging.debug("Running idle observers")
    for o in _idle_observers:
      o()

  def realized(self):
    return self.response is not None

  def _invoke_watches(self, response):
    watches = self.watches
    self.watches = None
    for watch in watches:
      watch(response)


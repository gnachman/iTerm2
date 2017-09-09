import _future as future
import logging

class DependentFuture(future.Future):
  """If you have a future A and you want to create future B, but B can't be
  created yet because the information needed to make it doesn't exist yet, use
  this. This provides a future C that creates B when A is realized. Its get()
  blocks until A and B are both realized."""
  def __init__(self, parent, create_inner):
    """Initializer.

    parent: The future this object depends on (future A)
    create_inner: A function that takes parent's response as its argument and
      returns a new future (future B)
    """
    future.Future.__init__(self)
    self.parent = parent
    self.innerFuture = None
    self.create_inner = create_inner
    parent.watch(self._parent_did_realize)

  def get(self):
    """Waits until both the parent and the subordinate futures (A and B) are
    realized. Return's B's value."""
    logging.debug("Dependent future %s getting parent future %s" % (str(self), str(self.parent)))
    parent = self.parent.get()
    logging.debug("Dependent future %s got parent from future %s, produced inner future %s" % (str(self), str(self.parent), str(self.innerFuture)))
    return self.innerFuture.get()

  def _parent_did_realize(self, response):
    logging.debug("PARENT REALIZED FOR %s" % str(self.parent))
    self.innerFuture = self.create_inner(response)
    for watch in self.watches:
      self.innerFuture.watch(watch)
    self.watches = None


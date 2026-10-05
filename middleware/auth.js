// Builds a /login?redirect=... URL so the person lands back where they
// started once they log in, instead of losing their place.
function buildLoginRedirect(req) {
  const target = req.method === 'GET' ? req.originalUrl : req.get('Referrer') || '/';
  return '/login?redirect=' + encodeURIComponent(target);
}

function requireLogin(req, res, next) {
  if (!req.session.user) return res.redirect(buildLoginRedirect(req));
  next();
}

function requireStudent(req, res, next) {
  if (!req.session.user) return res.redirect(buildLoginRedirect(req));
  if (req.session.user.role !== 'student') {
    return res.status(403).send('Students only.');
  }
  next();
}

function requireKitchenOwner(req, res, next) {
  if (!req.session.user) return res.redirect(buildLoginRedirect(req));
  if (req.session.user.role !== 'kitchen_owner') {
    return res.status(403).send('Kitchen owners only.');
  }
  next();
}

function requireAdmin(req, res, next) {
  if (!req.session.user) return res.redirect(buildLoginRedirect(req));
  if (req.session.user.role !== 'admin') {
    return res.status(403).send('Admin access only.');
  }
  next();
}

module.exports = { requireLogin, requireStudent, requireKitchenOwner, requireAdmin };

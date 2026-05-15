-- Parkitect Initial Schema - Phase 0
-- Complete multi-tenant parking lot intelligence platform
-- Includes PostGIS, RLS, audit trails, and inspection workflows

-- ============================================================================
-- EXTENSIONS
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS http;

-- ============================================================================
-- ENUMS
-- ============================================================================

CREATE TYPE organization_role AS ENUM (
  'owner',
  'admin',
  'manager',
  'operator',
  'viewer'
);

CREATE TYPE feature_type AS ENUM (
  'section', 'marking', 'zone', 'row', 'line', 'hash', 'stop_bar', 'arrow',
  'curb', 'fire_lane', 'access_aisle', 'accessible_space', 'crosswalk',
  'loading_zone', 'delivery_zone', 'ev_zone', 'pickup_dropoff_zone',
  'wheel_stop', 'future_design_zone', 'sign', 'note_anchor', 'path'
);

CREATE TYPE condition_rating AS ENUM (
  'Good',
  'Monitor',
  'Fading',
  'Touch-Up Needed',
  'Touched Up',
  'Full Repaint Recommended',
  'Redesign Candidate',
  'Affiliate Review Recommended',
  'Customer Approval Needed'
);

CREATE TYPE revision_status AS ENUM (
  'draft',
  'published',
  'archived'
);

CREATE TYPE inspection_status AS ENUM (
  'scheduled',
  'in_progress',
  'completed',
  'cancelled'
);

CREATE TYPE inspection_priority AS ENUM (
  'low',
  'medium',
  'high',
  'critical'
);

-- ============================================================================
-- ORGANIZATIONS (Multi-Tenant Root)
-- ============================================================================

CREATE TABLE organizations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  plan TEXT DEFAULT 'starter',
  billing_email TEXT,
  settings JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_organizations_plan ON organizations(plan);

-- ============================================================================
-- USERS & MEMBERSHIPS
-- ============================================================================

CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  auth_user_id UUID UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name TEXT,
  email TEXT UNIQUE,
  avatar_url TEXT,
  preferences JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_auth_user_id ON users(auth_user_id);

CREATE TABLE memberships (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role organization_role NOT NULL DEFAULT 'viewer',
  status TEXT DEFAULT 'active',
  invited_by UUID REFERENCES users(id),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(organization_id, user_id)
);

CREATE INDEX idx_memberships_org_user ON memberships(organization_id, user_id);
CREATE INDEX idx_memberships_user ON memberships(user_id);
CREATE INDEX idx_memberships_role ON memberships(organization_id, role);

-- ============================================================================
-- CUSTOMERS & PROPERTIES
-- ============================================================================

CREATE TABLE customers (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  crm_primary_system TEXT,
  crm_primary_ref TEXT,
  contact_email TEXT,
  contact_phone TEXT,
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_customers_org ON customers(organization_id);
CREATE INDEX idx_customers_crm ON customers(organization_id, crm_primary_system, crm_primary_ref);

CREATE TABLE properties (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  customer_id UUID REFERENCES customers(id) ON DELETE SET NULL,
  name TEXT NOT NULL,
  address TEXT,
  city TEXT,
  state TEXT,
  postal_code TEXT,
  country TEXT DEFAULT 'US',
  lat DOUBLE PRECISION,
  lng DOUBLE PRECISION,
  location GEOGRAPHY(POINT, 4326),
  sqft INT,
  notes JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_properties_org ON properties(organization_id);
CREATE INDEX idx_properties_customer ON properties(customer_id);
CREATE INDEX idx_properties_location ON properties USING GIST(location);

-- ============================================================================
-- PARKING LOTS & BACKGROUNDS
-- ============================================================================

CREATE TABLE parking_lots (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  property_id UUID REFERENCES properties(id) ON DELETE SET NULL,
  name TEXT NOT NULL,
  description TEXT,
  default_background_id UUID,
  active_revision_id BIGINT,
  total_spaces INT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_parking_lots_org ON parking_lots(organization_id);
CREATE INDEX idx_parking_lots_property ON parking_lots(property_id);

CREATE TABLE lot_backgrounds (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  parking_lot_id UUID NOT NULL REFERENCES parking_lots(id) ON DELETE CASCADE,
  type TEXT NOT NULL CHECK (type IN ('aerial_map', 'uploaded_image', 'drone_ortho', 'plan')),
  source_provider TEXT,
  source_uri TEXT,
  storage_path TEXT,
  width INT,
  height INT,
  scale_ratio NUMERIC,
  georef_json JSONB,
  attribution_json JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_lot_backgrounds_lot ON lot_backgrounds(parking_lot_id);
CREATE INDEX idx_lot_backgrounds_type ON lot_backgrounds(type);

-- ============================================================================
-- LOT REVISIONS & FEATURES
-- ============================================================================

CREATE TABLE lot_revisions (
  id BIGSERIAL PRIMARY KEY,
  organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  parking_lot_id UUID NOT NULL REFERENCES parking_lots(id) ON DELETE CASCADE,
  revision_no INT NOT NULL,
  based_on_revision_id BIGINT REFERENCES lot_revisions(id) ON DELETE SET NULL,
  status revision_status DEFAULT 'draft',
  created_by UUID REFERENCES users(id) ON DELETE SET NULL,
  published_by UUID REFERENCES users(id) ON DELETE SET NULL,
  published_at TIMESTAMPTZ,
  title TEXT,
  description TEXT,
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(parking_lot_id, revision_no)
);

CREATE INDEX idx_lot_revisions_lot ON lot_revisions(parking_lot_id);
CREATE INDEX idx_lot_revisions_org ON lot_revisions(organization_id);
CREATE INDEX idx_lot_revisions_status ON lot_revisions(status);
CREATE INDEX idx_lot_revisions_created_by ON lot_revisions(created_by);

CREATE TABLE lot_features (
  id BIGSERIAL PRIMARY KEY,
  organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  parking_lot_id UUID NOT NULL REFERENCES parking_lots(id) ON DELETE CASCADE,
  revision_id BIGINT NOT NULL REFERENCES lot_revisions(id) ON DELETE CASCADE,
  feature_uuid UUID NOT NULL DEFAULT uuid_generate_v4(),
  parent_feature_uuid UUID,
  feature_type feature_type NOT NULL,
  label TEXT,
  description TEXT,
  geom GEOMETRY(GEOMETRY, 4326),
  image_geometry JSONB,
  style_json JSONB DEFAULT '{}',
  meta_json JSONB DEFAULT '{}',
  condition_rating condition_rating,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(parking_lot_id, feature_uuid)
);

CREATE INDEX idx_lot_features_lot ON lot_features(parking_lot_id);
CREATE INDEX idx_lot_features_revision ON lot_features(revision_id);
CREATE INDEX idx_lot_features_type ON lot_features(feature_type);
CREATE INDEX idx_lot_features_geom ON lot_features USING GIST(geom);
CREATE INDEX idx_lot_features_parent ON lot_features(parent_feature_uuid);

-- Generated columns for spatial analysis
ALTER TABLE lot_features ADD COLUMN centroid GEOMETRY GENERATED ALWAYS AS (ST_Centroid(geom)) STORED;
ALTER TABLE lot_features ADD COLUMN area_sqft NUMERIC GENERATED ALWAYS AS (
  CASE WHEN ST_GeometryType(geom) IN ('ST_Polygon', 'ST_MultiPolygon')
    THEN ROUND((ST_Area(geom::GEOGRAPHY) / 0.092903)::NUMERIC, 2)
    ELSE NULL
  END
) STORED;

CREATE INDEX idx_lot_features_centroid ON lot_features USING GIST(centroid);

-- ============================================================================
-- INSPECTIONS & FINDINGS
-- ============================================================================

CREATE TABLE inspections (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  parking_lot_id UUID NOT NULL REFERENCES parking_lots(id) ON DELETE CASCADE,
  revision_id BIGINT REFERENCES lot_revisions(id) ON DELETE SET NULL,
  assigned_to UUID REFERENCES users(id) ON DELETE SET NULL,
  created_by UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  status inspection_status DEFAULT 'scheduled',
  priority inspection_priority DEFAULT 'medium',
  title TEXT NOT NULL,
  description TEXT,
  scheduled_at TIMESTAMPTZ,
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  total_findings INT DEFAULT 0,
  critical_findings INT DEFAULT 0,
  notes JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_inspections_lot ON inspections(parking_lot_id);
CREATE INDEX idx_inspections_org ON inspections(organization_id);
CREATE INDEX idx_inspections_assigned ON inspections(assigned_to);
CREATE INDEX idx_inspections_status ON inspections(status);
CREATE INDEX idx_inspections_priority ON inspections(priority);

CREATE TABLE inspection_findings (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  inspection_id UUID NOT NULL REFERENCES inspections(id) ON DELETE CASCADE,
  feature_id BIGINT REFERENCES lot_features(id) ON DELETE SET NULL,
  finding_type TEXT NOT NULL,
  severity TEXT NOT NULL CHECK (severity IN ('low', 'medium', 'high', 'critical')),
  description TEXT NOT NULL,
  recommendation TEXT,
  geom GEOMETRY(POINT, 4326),
  photo_urls TEXT[] DEFAULT ARRAY[]::TEXT[],
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_inspection_findings_inspection ON inspection_findings(inspection_id);
CREATE INDEX idx_inspection_findings_feature ON inspection_findings(feature_id);
CREATE INDEX idx_inspection_findings_severity ON inspection_findings(severity);

-- ============================================================================
-- WORK ORDERS & COMPLIANCE
-- ============================================================================

CREATE TABLE work_orders (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  parking_lot_id UUID NOT NULL REFERENCES parking_lots(id) ON DELETE CASCADE,
  finding_id UUID REFERENCES inspection_findings(id) ON DELETE SET NULL,
  title TEXT NOT NULL,
  description TEXT,
  priority TEXT DEFAULT 'medium',
  status TEXT DEFAULT 'open' CHECK (status IN ('open', 'in_progress', 'completed', 'cancelled')),
  assigned_to UUID REFERENCES users(id) ON DELETE SET NULL,
  created_by UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  due_date DATE,
  completed_at TIMESTAMPTZ,
  cost_estimate NUMERIC,
  cost_actual NUMERIC,
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_work_orders_lot ON work_orders(parking_lot_id);
CREATE INDEX idx_work_orders_status ON work_orders(status);
CREATE INDEX idx_work_orders_assigned ON work_orders(assigned_to);

CREATE TABLE compliance_logs (
  id BIGSERIAL PRIMARY KEY,
  organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  action TEXT NOT NULL,
  actor_id UUID REFERENCES users(id) ON DELETE SET NULL,
  changes JSONB,
  metadata JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  CONSTRAINT compliance_logs_immutable UNIQUE(id)
);

CREATE INDEX idx_compliance_logs_org ON compliance_logs(organization_id);
CREATE INDEX idx_compliance_logs_entity ON compliance_logs(entity_type, entity_id);
CREATE INDEX idx_compliance_logs_created ON compliance_logs(created_at);

-- ============================================================================
-- ROW LEVEL SECURITY (RLS)
-- ============================================================================

-- Enable RLS on all tables
ALTER TABLE organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE properties ENABLE ROW LEVEL SECURITY;
ALTER TABLE parking_lots ENABLE ROW LEVEL SECURITY;
ALTER TABLE lot_backgrounds ENABLE ROW LEVEL SECURITY;
ALTER TABLE lot_revisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE lot_features ENABLE ROW LEVEL SECURITY;
ALTER TABLE inspections ENABLE ROW LEVEL SECURITY;
ALTER TABLE inspection_findings ENABLE ROW LEVEL SECURITY;
ALTER TABLE work_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE compliance_logs ENABLE ROW LEVEL SECURITY;

-- Organizations: Users can only see orgs they're members of
CREATE POLICY "org_member_select" ON organizations
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM memberships
      WHERE memberships.organization_id = organizations.id
        AND memberships.user_id = auth.uid()
    )
  );

-- Users: Can see own profile and other org members
CREATE POLICY "user_self_select" ON users
  FOR SELECT USING (id = auth.uid());

CREATE POLICY "user_org_member_select" ON users
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM memberships m1
      JOIN memberships m2 ON m1.organization_id = m2.organization_id
      WHERE m1.user_id = auth.uid()
        AND m2.user_id = users.id
    )
  );

-- Memberships: Users can see their org's memberships
CREATE POLICY "membership_org_select" ON memberships
  FOR SELECT USING (
    user_id = auth.uid() OR organization_id IN (
      SELECT organization_id FROM memberships WHERE user_id = auth.uid()
    )
  );

-- Customers: Organization isolation
CREATE POLICY "customer_org_isolation" ON customers
  FOR ALL USING (
    organization_id IN (
      SELECT organization_id FROM memberships WHERE user_id = auth.uid()
    )
  );

-- Properties: Organization isolation
CREATE POLICY "property_org_isolation" ON properties
  FOR ALL USING (
    organization_id IN (
      SELECT organization_id FROM memberships WHERE user_id = auth.uid()
    )
  );

-- Parking Lots: Organization isolation
CREATE POLICY "parking_lot_org_isolation" ON parking_lots
  FOR ALL USING (
    organization_id IN (
      SELECT organization_id FROM memberships WHERE user_id = auth.uid()
    )
  );

-- Lot Backgrounds: Organization isolation
CREATE POLICY "lot_background_org_isolation" ON lot_backgrounds
  FOR ALL USING (
    organization_id IN (
      SELECT organization_id FROM memberships WHERE user_id = auth.uid()
    )
  );

-- Lot Revisions: Organization isolation
CREATE POLICY "lot_revision_org_isolation" ON lot_revisions
  FOR ALL USING (
    organization_id IN (
      SELECT organization_id FROM memberships WHERE user_id = auth.uid()
    )
  );

-- Lot Features: Organization isolation
CREATE POLICY "lot_feature_org_isolation" ON lot_features
  FOR ALL USING (
    organization_id IN (
      SELECT organization_id FROM memberships WHERE user_id = auth.uid()
    )
  );

-- Inspections: Organization isolation
CREATE POLICY "inspection_org_isolation" ON inspections
  FOR ALL USING (
    organization_id IN (
      SELECT organization_id FROM memberships WHERE user_id = auth.uid()
    )
  );

-- Inspection Findings: Organization isolation
CREATE POLICY "inspection_finding_org_isolation" ON inspection_findings
  FOR ALL USING (
    organization_id IN (
      SELECT organization_id FROM memberships WHERE user_id = auth.uid()
    )
  );

-- Work Orders: Organization isolation
CREATE POLICY "work_order_org_isolation" ON work_orders
  FOR ALL USING (
    organization_id IN (
      SELECT organization_id FROM memberships WHERE user_id = auth.uid()
    )
  );

-- Compliance Logs: Organization isolation (read-only)
CREATE POLICY "compliance_log_org_isolation" ON compliance_logs
  FOR SELECT USING (
    organization_id IN (
      SELECT organization_id FROM memberships WHERE user_id = auth.uid()
    )
  );

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Get all organizations for current user
CREATE OR REPLACE FUNCTION get_user_organizations()
RETURNS TABLE (id UUID, name TEXT, role organization_role) AS $$
BEGIN
  RETURN QUERY
  SELECT o.id, o.name, m.role
  FROM organizations o
  JOIN memberships m ON o.id = m.organization_id
  WHERE m.user_id = auth.uid()
  ORDER BY o.name;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Check if user is member of organization with optional role check
CREATE OR REPLACE FUNCTION is_org_member(org_id UUID, check_role organization_role DEFAULT NULL)
RETURNS BOOLEAN AS $$
DECLARE
  user_role organization_role;
BEGIN
  SELECT role INTO user_role
  FROM memberships
  WHERE organization_id = org_id
    AND user_id = auth.uid()
  LIMIT 1;

  IF user_role IS NULL THEN
    RETURN FALSE;
  END IF;

  IF check_role IS NULL THEN
    RETURN TRUE;
  END IF;

  -- Role hierarchy: owner > admin > manager > operator > viewer
  RETURN CASE
    WHEN user_role = 'owner' THEN TRUE
    WHEN user_role = 'admin' AND check_role IN ('admin', 'manager', 'operator', 'viewer') THEN TRUE
    WHEN user_role = 'manager' AND check_role IN ('manager', 'operator', 'viewer') THEN TRUE
    WHEN user_role = 'operator' AND check_role IN ('operator', 'viewer') THEN TRUE
    WHEN user_role = 'viewer' AND check_role = 'viewer' THEN TRUE
    ELSE FALSE
  END;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- AUDIT TRIGGERS
-- ============================================================================

CREATE OR REPLACE FUNCTION audit_log_changes()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO compliance_logs (organization_id, entity_type, entity_id, action, actor_id, changes)
    VALUES (
      COALESCE(NEW.organization_id, (NEW::JSON->>'organization_id')::UUID),
      TG_TABLE_NAME,
      NEW.id::TEXT,
      'INSERT',
      auth.uid(),
      row_to_json(NEW)
    );
  ELSIF TG_OP = 'UPDATE' THEN
    INSERT INTO compliance_logs (organization_id, entity_type, entity_id, action, actor_id, changes)
    VALUES (
      COALESCE(NEW.organization_id, (NEW::JSON->>'organization_id')::UUID),
      TG_TABLE_NAME,
      NEW.id::TEXT,
      'UPDATE',
      auth.uid(),
      jsonb_build_object('before', row_to_json(OLD), 'after', row_to_json(NEW))
    );
  ELSIF TG_OP = 'DELETE' THEN
    INSERT INTO compliance_logs (organization_id, entity_type, entity_id, action, actor_id, changes)
    VALUES (
      COALESCE(OLD.organization_id, (OLD::JSON->>'organization_id')::UUID),
      TG_TABLE_NAME,
      OLD.id::TEXT,
      'DELETE',
      auth.uid(),
      row_to_json(OLD)
    );
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- Attach audit triggers to key tables
CREATE TRIGGER audit_parking_lots AFTER INSERT OR UPDATE OR DELETE ON parking_lots
  FOR EACH ROW EXECUTE FUNCTION audit_log_changes();

CREATE TRIGGER audit_lot_revisions AFTER INSERT OR UPDATE OR DELETE ON lot_revisions
  FOR EACH ROW EXECUTE FUNCTION audit_log_changes();

CREATE TRIGGER audit_inspections AFTER INSERT OR UPDATE OR DELETE ON inspections
  FOR EACH ROW EXECUTE FUNCTION audit_log_changes();

CREATE TRIGGER audit_work_orders AFTER INSERT OR UPDATE OR DELETE ON work_orders
  FOR EACH ROW EXECUTE FUNCTION audit_log_changes();

-- ============================================================================
-- GRANT PERMISSIONS
-- ============================================================================

GRANT USAGE ON SCHEMA public TO authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated;

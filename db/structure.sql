SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: actions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.actions (
    id bigint NOT NULL,
    shop_id bigint NOT NULL,
    customer_id bigint NOT NULL,
    action_type character varying NOT NULL,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    risk_tier character varying NOT NULL,
    revenue_at_risk numeric(10,2),
    proposed_discount character varying,
    reason character varying,
    expires_at timestamp(6) without time zone,
    approved_at timestamp(6) without time zone,
    skipped_at timestamp(6) without time zone,
    executed_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    treatment_key character varying,
    uplift_score numeric(6,4),
    expected_incremental_revenue numeric(10,2),
    model_version character varying,
    holdout boolean DEFAULT false NOT NULL,
    outcome_window_days integer
);

ALTER TABLE ONLY public.actions FORCE ROW LEVEL SECURITY;


--
-- Name: actions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.actions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: actions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.actions_id_seq OWNED BY public.actions.id;


--
-- Name: active_storage_attachments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_attachments (
    id bigint NOT NULL,
    name character varying NOT NULL,
    record_type character varying NOT NULL,
    record_id bigint NOT NULL,
    blob_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: active_storage_attachments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.active_storage_attachments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: active_storage_attachments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.active_storage_attachments_id_seq OWNED BY public.active_storage_attachments.id;


--
-- Name: active_storage_blobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_blobs (
    id bigint NOT NULL,
    key character varying NOT NULL,
    filename character varying NOT NULL,
    content_type character varying,
    metadata text,
    service_name character varying NOT NULL,
    byte_size bigint NOT NULL,
    checksum character varying,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: active_storage_blobs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.active_storage_blobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: active_storage_blobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.active_storage_blobs_id_seq OWNED BY public.active_storage_blobs.id;


--
-- Name: active_storage_variant_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_variant_records (
    id bigint NOT NULL,
    blob_id bigint NOT NULL,
    variation_digest character varying NOT NULL
);


--
-- Name: active_storage_variant_records_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.active_storage_variant_records_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: active_storage_variant_records_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.active_storage_variant_records_id_seq OWNED BY public.active_storage_variant_records.id;


--
-- Name: analysis_predictions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.analysis_predictions (
    id bigint NOT NULL,
    analysis_run_id bigint NOT NULL,
    rank integer NOT NULL,
    customer_key_hash character varying NOT NULL,
    customer_label character varying NOT NULL,
    uplift_score numeric(8,6) NOT NULL,
    probability_treatment numeric(8,6) NOT NULL,
    probability_control numeric(8,6) NOT NULL,
    average_order_value numeric(12,2) DEFAULT 0.0 NOT NULL,
    expected_incremental_revenue numeric(12,2) DEFAULT 0.0 NOT NULL,
    expected_incremental_profit numeric(12,2) DEFAULT 0.0 NOT NULL,
    segment character varying NOT NULL,
    recommended_action character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: analysis_predictions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.analysis_predictions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: analysis_predictions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.analysis_predictions_id_seq OWNED BY public.analysis_predictions.id;


--
-- Name: analysis_projects; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.analysis_projects (
    id bigint NOT NULL,
    sandbox_user_id bigint NOT NULL,
    name character varying NOT NULL,
    status character varying DEFAULT 'uploaded'::character varying NOT NULL,
    mode character varying,
    column_mapping jsonb DEFAULT '{}'::jsonb NOT NULL,
    data_audit jsonb DEFAULT '{}'::jsonb NOT NULL,
    campaign_date date,
    outcome_window_days integer DEFAULT 30 NOT NULL,
    gross_margin_rate numeric(6,4) DEFAULT 0.4 NOT NULL,
    discount_rate numeric(6,4) DEFAULT 0.1 NOT NULL,
    contact_cost numeric(10,2) DEFAULT 0.0 NOT NULL,
    randomized_treatment boolean DEFAULT false NOT NULL,
    error_message text,
    raw_expires_at timestamp(6) without time zone NOT NULL,
    results_expires_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: analysis_projects_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.analysis_projects_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: analysis_projects_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.analysis_projects_id_seq OWNED BY public.analysis_projects.id;


--
-- Name: analysis_runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.analysis_runs (
    id bigint NOT NULL,
    analysis_project_id bigint NOT NULL,
    status character varying DEFAULT 'queued'::character varying NOT NULL,
    evidence_type character varying,
    model_version character varying,
    seed integer DEFAULT 42 NOT NULL,
    metrics jsonb DEFAULT '{}'::jsonb NOT NULL,
    deciles jsonb DEFAULT '[]'::jsonb NOT NULL,
    warnings jsonb DEFAULT '[]'::jsonb NOT NULL,
    error_message text,
    started_at timestamp(6) without time zone,
    completed_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: analysis_runs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.analysis_runs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: analysis_runs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.analysis_runs_id_seq OWNED BY public.analysis_runs.id;


--
-- Name: approval_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.approval_tokens (
    id bigint NOT NULL,
    action_id bigint NOT NULL,
    token_hash character varying NOT NULL,
    expires_at timestamp(6) without time zone NOT NULL,
    consumed_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);

ALTER TABLE ONLY public.approval_tokens FORCE ROW LEVEL SECURITY;


--
-- Name: approval_tokens_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.approval_tokens_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: approval_tokens_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.approval_tokens_id_seq OWNED BY public.approval_tokens.id;


--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: customers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.customers (
    id bigint NOT NULL,
    shop_id bigint NOT NULL,
    shopify_customer_id character varying NOT NULL,
    email character varying,
    name character varying,
    lifetime_value numeric(10,2) DEFAULT 0.0,
    risk_tier character varying,
    risk_score numeric(5,4),
    last_scored_on date,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    uplift_score numeric(6,4),
    expected_incremental_revenue numeric(10,2),
    uplift_treatment_key character varying,
    uplift_model_version character varying,
    uplift_scored_on date
);

ALTER TABLE ONLY public.customers FORCE ROW LEVEL SECURITY;


--
-- Name: customers_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.customers_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: customers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.customers_id_seq OWNED BY public.customers.id;


--
-- Name: events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.events (
    id bigint NOT NULL,
    shop_id bigint NOT NULL,
    customer_id bigint,
    event_type character varying NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    shopify_webhook_id character varying,
    occurred_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);

ALTER TABLE ONLY public.events FORCE ROW LEVEL SECURITY;


--
-- Name: events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.events_id_seq OWNED BY public.events.id;


--
-- Name: execution_queue_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.execution_queue_items (
    id bigint NOT NULL,
    action_id bigint NOT NULL,
    status character varying DEFAULT 'queued'::character varying NOT NULL,
    attempts integer DEFAULT 0 NOT NULL,
    last_error character varying,
    last_attempted_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);

ALTER TABLE ONLY public.execution_queue_items FORCE ROW LEVEL SECURITY;


--
-- Name: execution_queue_items_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.execution_queue_items_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: execution_queue_items_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.execution_queue_items_id_seq OWNED BY public.execution_queue_items.id;


--
-- Name: orders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.orders (
    id bigint NOT NULL,
    shop_id bigint NOT NULL,
    customer_id bigint NOT NULL,
    shopify_order_id character varying NOT NULL,
    amount numeric(10,2) NOT NULL,
    currency character varying DEFAULT 'EUR'::character varying,
    status character varying DEFAULT 'paid'::character varying,
    ordered_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);

ALTER TABLE ONLY public.orders FORCE ROW LEVEL SECURITY;


--
-- Name: orders_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.orders_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: orders_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.orders_id_seq OWNED BY public.orders.id;


--
-- Name: sandbox_magic_links; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sandbox_magic_links (
    id bigint NOT NULL,
    sandbox_user_id bigint NOT NULL,
    token_digest character varying NOT NULL,
    expires_at timestamp(6) without time zone NOT NULL,
    consumed_at timestamp(6) without time zone,
    request_ip character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: sandbox_magic_links_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sandbox_magic_links_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sandbox_magic_links_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sandbox_magic_links_id_seq OWNED BY public.sandbox_magic_links.id;


--
-- Name: sandbox_users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sandbox_users (
    id bigint NOT NULL,
    email character varying NOT NULL,
    last_signed_in_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: sandbox_users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sandbox_users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sandbox_users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sandbox_users_id_seq OWNED BY public.sandbox_users.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: shops; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.shops (
    id bigint NOT NULL,
    shopify_domain character varying NOT NULL,
    shopify_token character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    klaviyo_api_key character varying,
    owner_email character varying
);


--
-- Name: shops_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.shops_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: shops_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.shops_id_seq OWNED BY public.shops.id;


--
-- Name: waitlist_signups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.waitlist_signups (
    id bigint NOT NULL,
    email character varying NOT NULL,
    shop_domain character varying,
    monthly_orders character varying,
    source character varying DEFAULT 'landing'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: waitlist_signups_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.waitlist_signups_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: waitlist_signups_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.waitlist_signups_id_seq OWNED BY public.waitlist_signups.id;


--
-- Name: webhook_deduplications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.webhook_deduplications (
    id bigint NOT NULL,
    shop_id bigint NOT NULL,
    webhook_id character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);

ALTER TABLE ONLY public.webhook_deduplications FORCE ROW LEVEL SECURITY;


--
-- Name: webhook_deduplications_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.webhook_deduplications_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: webhook_deduplications_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.webhook_deduplications_id_seq OWNED BY public.webhook_deduplications.id;


--
-- Name: actions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.actions ALTER COLUMN id SET DEFAULT nextval('public.actions_id_seq'::regclass);


--
-- Name: active_storage_attachments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments ALTER COLUMN id SET DEFAULT nextval('public.active_storage_attachments_id_seq'::regclass);


--
-- Name: active_storage_blobs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_blobs ALTER COLUMN id SET DEFAULT nextval('public.active_storage_blobs_id_seq'::regclass);


--
-- Name: active_storage_variant_records id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records ALTER COLUMN id SET DEFAULT nextval('public.active_storage_variant_records_id_seq'::regclass);


--
-- Name: analysis_predictions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.analysis_predictions ALTER COLUMN id SET DEFAULT nextval('public.analysis_predictions_id_seq'::regclass);


--
-- Name: analysis_projects id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.analysis_projects ALTER COLUMN id SET DEFAULT nextval('public.analysis_projects_id_seq'::regclass);


--
-- Name: analysis_runs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.analysis_runs ALTER COLUMN id SET DEFAULT nextval('public.analysis_runs_id_seq'::regclass);


--
-- Name: approval_tokens id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_tokens ALTER COLUMN id SET DEFAULT nextval('public.approval_tokens_id_seq'::regclass);


--
-- Name: customers id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers ALTER COLUMN id SET DEFAULT nextval('public.customers_id_seq'::regclass);


--
-- Name: events id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events ALTER COLUMN id SET DEFAULT nextval('public.events_id_seq'::regclass);


--
-- Name: execution_queue_items id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.execution_queue_items ALTER COLUMN id SET DEFAULT nextval('public.execution_queue_items_id_seq'::regclass);


--
-- Name: orders id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders ALTER COLUMN id SET DEFAULT nextval('public.orders_id_seq'::regclass);


--
-- Name: sandbox_magic_links id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sandbox_magic_links ALTER COLUMN id SET DEFAULT nextval('public.sandbox_magic_links_id_seq'::regclass);


--
-- Name: sandbox_users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sandbox_users ALTER COLUMN id SET DEFAULT nextval('public.sandbox_users_id_seq'::regclass);


--
-- Name: shops id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shops ALTER COLUMN id SET DEFAULT nextval('public.shops_id_seq'::regclass);


--
-- Name: waitlist_signups id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.waitlist_signups ALTER COLUMN id SET DEFAULT nextval('public.waitlist_signups_id_seq'::regclass);


--
-- Name: webhook_deduplications id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webhook_deduplications ALTER COLUMN id SET DEFAULT nextval('public.webhook_deduplications_id_seq'::regclass);


--
-- Name: actions actions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.actions
    ADD CONSTRAINT actions_pkey PRIMARY KEY (id);


--
-- Name: active_storage_attachments active_storage_attachments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments
    ADD CONSTRAINT active_storage_attachments_pkey PRIMARY KEY (id);


--
-- Name: active_storage_blobs active_storage_blobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_blobs
    ADD CONSTRAINT active_storage_blobs_pkey PRIMARY KEY (id);


--
-- Name: active_storage_variant_records active_storage_variant_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records
    ADD CONSTRAINT active_storage_variant_records_pkey PRIMARY KEY (id);


--
-- Name: analysis_predictions analysis_predictions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.analysis_predictions
    ADD CONSTRAINT analysis_predictions_pkey PRIMARY KEY (id);


--
-- Name: analysis_projects analysis_projects_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.analysis_projects
    ADD CONSTRAINT analysis_projects_pkey PRIMARY KEY (id);


--
-- Name: analysis_runs analysis_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.analysis_runs
    ADD CONSTRAINT analysis_runs_pkey PRIMARY KEY (id);


--
-- Name: approval_tokens approval_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_tokens
    ADD CONSTRAINT approval_tokens_pkey PRIMARY KEY (id);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: customers customers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_pkey PRIMARY KEY (id);


--
-- Name: events events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT events_pkey PRIMARY KEY (id);


--
-- Name: execution_queue_items execution_queue_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.execution_queue_items
    ADD CONSTRAINT execution_queue_items_pkey PRIMARY KEY (id);


--
-- Name: orders orders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_pkey PRIMARY KEY (id);


--
-- Name: sandbox_magic_links sandbox_magic_links_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sandbox_magic_links
    ADD CONSTRAINT sandbox_magic_links_pkey PRIMARY KEY (id);


--
-- Name: sandbox_users sandbox_users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sandbox_users
    ADD CONSTRAINT sandbox_users_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: shops shops_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shops
    ADD CONSTRAINT shops_pkey PRIMARY KEY (id);


--
-- Name: waitlist_signups waitlist_signups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.waitlist_signups
    ADD CONSTRAINT waitlist_signups_pkey PRIMARY KEY (id);


--
-- Name: webhook_deduplications webhook_deduplications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webhook_deduplications
    ADD CONSTRAINT webhook_deduplications_pkey PRIMARY KEY (id);


--
-- Name: index_actions_on_customer_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_actions_on_customer_id ON public.actions USING btree (customer_id);


--
-- Name: index_actions_on_shop_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_actions_on_shop_id ON public.actions USING btree (shop_id);


--
-- Name: index_actions_on_shop_id_and_holdout; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_actions_on_shop_id_and_holdout ON public.actions USING btree (shop_id, holdout);


--
-- Name: index_actions_on_shop_id_and_model_version; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_actions_on_shop_id_and_model_version ON public.actions USING btree (shop_id, model_version);


--
-- Name: index_actions_on_shop_id_and_treatment_key; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_actions_on_shop_id_and_treatment_key ON public.actions USING btree (shop_id, treatment_key);


--
-- Name: index_active_storage_attachments_on_blob_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_active_storage_attachments_on_blob_id ON public.active_storage_attachments USING btree (blob_id);


--
-- Name: index_active_storage_attachments_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_attachments_uniqueness ON public.active_storage_attachments USING btree (record_type, record_id, name, blob_id);


--
-- Name: index_active_storage_blobs_on_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_blobs_on_key ON public.active_storage_blobs USING btree (key);


--
-- Name: index_active_storage_variant_records_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_variant_records_uniqueness ON public.active_storage_variant_records USING btree (blob_id, variation_digest);


--
-- Name: index_analysis_predictions_on_analysis_run_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_analysis_predictions_on_analysis_run_id ON public.analysis_predictions USING btree (analysis_run_id);


--
-- Name: index_analysis_predictions_on_analysis_run_id_and_rank; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_analysis_predictions_on_analysis_run_id_and_rank ON public.analysis_predictions USING btree (analysis_run_id, rank);


--
-- Name: index_analysis_projects_on_raw_expires_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_analysis_projects_on_raw_expires_at ON public.analysis_projects USING btree (raw_expires_at);


--
-- Name: index_analysis_projects_on_results_expires_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_analysis_projects_on_results_expires_at ON public.analysis_projects USING btree (results_expires_at);


--
-- Name: index_analysis_projects_on_sandbox_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_analysis_projects_on_sandbox_user_id ON public.analysis_projects USING btree (sandbox_user_id);


--
-- Name: index_analysis_projects_on_sandbox_user_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_analysis_projects_on_sandbox_user_id_and_created_at ON public.analysis_projects USING btree (sandbox_user_id, created_at);


--
-- Name: index_analysis_projects_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_analysis_projects_on_status ON public.analysis_projects USING btree (status);


--
-- Name: index_analysis_runs_on_analysis_project_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_analysis_runs_on_analysis_project_id ON public.analysis_runs USING btree (analysis_project_id);


--
-- Name: index_analysis_runs_on_analysis_project_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_analysis_runs_on_analysis_project_id_and_created_at ON public.analysis_runs USING btree (analysis_project_id, created_at);


--
-- Name: index_analysis_runs_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_analysis_runs_on_status ON public.analysis_runs USING btree (status);


--
-- Name: index_approval_tokens_on_action_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_approval_tokens_on_action_id ON public.approval_tokens USING btree (action_id);


--
-- Name: index_approval_tokens_on_token_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_approval_tokens_on_token_hash ON public.approval_tokens USING btree (token_hash);


--
-- Name: index_customers_on_shop_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_customers_on_shop_id ON public.customers USING btree (shop_id);


--
-- Name: index_customers_on_shop_id_and_shopify_customer_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_customers_on_shop_id_and_shopify_customer_id ON public.customers USING btree (shop_id, shopify_customer_id);


--
-- Name: index_customers_on_shop_id_and_uplift_model_version; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_customers_on_shop_id_and_uplift_model_version ON public.customers USING btree (shop_id, uplift_model_version);


--
-- Name: index_events_on_customer_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_events_on_customer_id ON public.events USING btree (customer_id);


--
-- Name: index_events_on_shop_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_events_on_shop_id ON public.events USING btree (shop_id);


--
-- Name: index_events_on_shop_id_and_event_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_events_on_shop_id_and_event_type ON public.events USING btree (shop_id, event_type);


--
-- Name: index_execution_queue_items_on_action_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_execution_queue_items_on_action_id ON public.execution_queue_items USING btree (action_id);


--
-- Name: index_orders_on_customer_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_orders_on_customer_id ON public.orders USING btree (customer_id);


--
-- Name: index_orders_on_shop_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_orders_on_shop_id ON public.orders USING btree (shop_id);


--
-- Name: index_orders_on_shop_id_and_shopify_order_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_orders_on_shop_id_and_shopify_order_id ON public.orders USING btree (shop_id, shopify_order_id);


--
-- Name: index_sandbox_magic_links_on_expires_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sandbox_magic_links_on_expires_at ON public.sandbox_magic_links USING btree (expires_at);


--
-- Name: index_sandbox_magic_links_on_sandbox_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sandbox_magic_links_on_sandbox_user_id ON public.sandbox_magic_links USING btree (sandbox_user_id);


--
-- Name: index_sandbox_magic_links_on_token_digest; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_sandbox_magic_links_on_token_digest ON public.sandbox_magic_links USING btree (token_digest);


--
-- Name: index_sandbox_users_on_lower_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_sandbox_users_on_lower_email ON public.sandbox_users USING btree (lower((email)::text));


--
-- Name: index_shops_on_shopify_domain; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_shops_on_shopify_domain ON public.shops USING btree (shopify_domain);


--
-- Name: index_waitlist_signups_on_lower_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_waitlist_signups_on_lower_email ON public.waitlist_signups USING btree (lower((email)::text));


--
-- Name: index_webhook_deduplications_on_shop_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_webhook_deduplications_on_shop_id ON public.webhook_deduplications USING btree (shop_id);


--
-- Name: index_webhook_deduplications_on_shop_id_and_webhook_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_webhook_deduplications_on_shop_id_and_webhook_id ON public.webhook_deduplications USING btree (shop_id, webhook_id);


--
-- Name: one_pending_per_customer; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX one_pending_per_customer ON public.actions USING btree (shop_id, customer_id) WHERE ((status)::text = 'pending'::text);


--
-- Name: customers fk_rails_10a49a9b12; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT fk_rails_10a49a9b12 FOREIGN KEY (shop_id) REFERENCES public.shops(id);


--
-- Name: webhook_deduplications fk_rails_31d5c2f83e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webhook_deduplications
    ADD CONSTRAINT fk_rails_31d5c2f83e FOREIGN KEY (shop_id) REFERENCES public.shops(id);


--
-- Name: orders fk_rails_3dad120da9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT fk_rails_3dad120da9 FOREIGN KEY (customer_id) REFERENCES public.customers(id);


--
-- Name: analysis_predictions fk_rails_41eed53c40; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.analysis_predictions
    ADD CONSTRAINT fk_rails_41eed53c40 FOREIGN KEY (analysis_run_id) REFERENCES public.analysis_runs(id);


--
-- Name: actions fk_rails_4b70265c78; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.actions
    ADD CONSTRAINT fk_rails_4b70265c78 FOREIGN KEY (shop_id) REFERENCES public.shops(id);


--
-- Name: events fk_rails_64995045bd; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT fk_rails_64995045bd FOREIGN KEY (customer_id) REFERENCES public.customers(id);


--
-- Name: execution_queue_items fk_rails_7d1cf56017; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.execution_queue_items
    ADD CONSTRAINT fk_rails_7d1cf56017 FOREIGN KEY (action_id) REFERENCES public.actions(id);


--
-- Name: sandbox_magic_links fk_rails_7d7d9ee6a5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sandbox_magic_links
    ADD CONSTRAINT fk_rails_7d7d9ee6a5 FOREIGN KEY (sandbox_user_id) REFERENCES public.sandbox_users(id);


--
-- Name: orders fk_rails_7e761c2e1b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT fk_rails_7e761c2e1b FOREIGN KEY (shop_id) REFERENCES public.shops(id);


--
-- Name: analysis_projects fk_rails_8d37bde248; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.analysis_projects
    ADD CONSTRAINT fk_rails_8d37bde248 FOREIGN KEY (sandbox_user_id) REFERENCES public.sandbox_users(id);


--
-- Name: active_storage_variant_records fk_rails_993965df05; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records
    ADD CONSTRAINT fk_rails_993965df05 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id);


--
-- Name: approval_tokens fk_rails_a08f2a21f0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_tokens
    ADD CONSTRAINT fk_rails_a08f2a21f0 FOREIGN KEY (action_id) REFERENCES public.actions(id);


--
-- Name: active_storage_attachments fk_rails_c3b3935057; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments
    ADD CONSTRAINT fk_rails_c3b3935057 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id);


--
-- Name: actions fk_rails_d3cbaf0228; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.actions
    ADD CONSTRAINT fk_rails_d3cbaf0228 FOREIGN KEY (customer_id) REFERENCES public.customers(id);


--
-- Name: analysis_runs fk_rails_efc81d2719; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.analysis_runs
    ADD CONSTRAINT fk_rails_efc81d2719 FOREIGN KEY (analysis_project_id) REFERENCES public.analysis_projects(id);


--
-- Name: events fk_rails_f418fcd900; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT fk_rails_f418fcd900 FOREIGN KEY (shop_id) REFERENCES public.shops(id);


--
-- Name: actions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.actions ENABLE ROW LEVEL SECURITY;

--
-- Name: approval_tokens; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.approval_tokens ENABLE ROW LEVEL SECURITY;

--
-- Name: customers; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;

--
-- Name: events; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.events ENABLE ROW LEVEL SECURITY;

--
-- Name: execution_queue_items; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.execution_queue_items ENABLE ROW LEVEL SECURITY;

--
-- Name: orders; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

--
-- Name: actions shop_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY shop_isolation ON public.actions USING ((shop_id = (NULLIF(current_setting('app.current_shop_id'::text, true), ''::text))::bigint));


--
-- Name: approval_tokens shop_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY shop_isolation ON public.approval_tokens USING ((action_id IN ( SELECT actions.id
   FROM public.actions
  WHERE (actions.shop_id = (NULLIF(current_setting('app.current_shop_id'::text, true), ''::text))::bigint))));


--
-- Name: customers shop_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY shop_isolation ON public.customers USING ((shop_id = (NULLIF(current_setting('app.current_shop_id'::text, true), ''::text))::bigint));


--
-- Name: events shop_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY shop_isolation ON public.events USING ((shop_id = (NULLIF(current_setting('app.current_shop_id'::text, true), ''::text))::bigint));


--
-- Name: execution_queue_items shop_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY shop_isolation ON public.execution_queue_items USING ((action_id IN ( SELECT actions.id
   FROM public.actions
  WHERE (actions.shop_id = (NULLIF(current_setting('app.current_shop_id'::text, true), ''::text))::bigint))));


--
-- Name: orders shop_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY shop_isolation ON public.orders USING ((shop_id = (NULLIF(current_setting('app.current_shop_id'::text, true), ''::text))::bigint));


--
-- Name: webhook_deduplications shop_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY shop_isolation ON public.webhook_deduplications USING ((shop_id = (NULLIF(current_setting('app.current_shop_id'::text, true), ''::text))::bigint));


--
-- Name: webhook_deduplications; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.webhook_deduplications ENABLE ROW LEVEL SECURITY;

--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20260928090100'),
('20260928090000'),
('20260704160000'),
('20260702090000'),
('20260628192306'),
('20260527200001'),
('20260527200000'),
('20260527171924'),
('20260527150324'),
('20260527150027');


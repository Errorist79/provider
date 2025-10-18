-- Minimal Unkey Schema for RPC Gateway
-- Contains only the tables needed for API key verification
-- Removed: Vercel integration, RBAC, deployments, ACME, audit logs

USE unkey;

-- Workspaces: Root workspace for key management
CREATE TABLE `workspaces` (
	`id` varchar(256) NOT NULL,
	`org_id` varchar(256) NOT NULL,
	`name` varchar(256) NOT NULL,
	`slug` varchar(64) NOT NULL,
	`plan` enum('free','pro','enterprise') DEFAULT 'free',
	`tier` varchar(256) DEFAULT 'Free',
	`beta_features` json NOT NULL,
	`features` json NOT NULL,
	`enabled` boolean NOT NULL DEFAULT true,
	`created_at_m` bigint NOT NULL DEFAULT 0,
	`updated_at_m` bigint,
	CONSTRAINT `workspaces_id` PRIMARY KEY(`id`),
	CONSTRAINT `workspaces_org_id_unique` UNIQUE(`org_id`),
	CONSTRAINT `workspaces_slug_unique` UNIQUE(`slug`)
);

-- Key Auth: API configuration
CREATE TABLE `key_auth` (
	`id` varchar(256) NOT NULL,
	`workspace_id` varchar(256) NOT NULL,
	`created_at_m` bigint NOT NULL DEFAULT 0,
	`updated_at_m` bigint,
	`default_prefix` varchar(8),
	`default_bytes` int DEFAULT 16,
	CONSTRAINT `key_auth_id` PRIMARY KEY(`id`)
);

-- APIs: API definitions
CREATE TABLE `apis` (
	`id` varchar(256) NOT NULL,
	`name` varchar(256) NOT NULL,
	`workspace_id` varchar(256) NOT NULL,
	`ip_whitelist` varchar(512),
	`auth_type` enum('key','jwt'),
	`key_auth_id` varchar(256),
	`created_at_m` bigint NOT NULL DEFAULT 0,
	`updated_at_m` bigint,
	CONSTRAINT `apis_id` PRIMARY KEY(`id`),
	CONSTRAINT `apis_key_auth_id_unique` UNIQUE(`key_auth_id`)
);

-- Keys: API keys (root key + customer keys)
CREATE TABLE `keys` (
	`id` varchar(256) NOT NULL,
	`key_auth_id` varchar(256) NOT NULL,
	`hash` varchar(256) NOT NULL,
	`start` varchar(256) NOT NULL,
	`workspace_id` varchar(256) NOT NULL,
	`for_workspace_id` varchar(256),
	`name` varchar(256),
	`owner_id` varchar(256),
	`identity_id` varchar(256),
	`meta` text,
	`expires` datetime(3),
	`created_at_m` bigint NOT NULL DEFAULT 0,
	`updated_at_m` bigint,
	`deleted_at_m` bigint,
	`enabled` boolean NOT NULL DEFAULT true,
	`remaining_requests` int,
	`refill_day` tinyint,
	`refill_amount` int,
	`last_refill_at` datetime(3),
	`ratelimit_async` boolean,
	`ratelimit_limit` int,
	`ratelimit_duration` bigint,
	`environment` varchar(256),
	CONSTRAINT `keys_id` PRIMARY KEY(`id`),
	CONSTRAINT `hash_idx` UNIQUE(`hash`)
);

-- Permissions: Permission definitions
CREATE TABLE `permissions` (
	`id` varchar(256) NOT NULL,
	`workspace_id` varchar(256) NOT NULL,
	`name` varchar(512) NOT NULL,
	`slug` varchar(128) NOT NULL,
	`description` varchar(512),
	`created_at_m` bigint NOT NULL DEFAULT 0,
	`updated_at_m` bigint,
	CONSTRAINT `permissions_id` PRIMARY KEY(`id`),
	CONSTRAINT `unique_slug_per_workspace_idx` UNIQUE(`workspace_id`,`slug`)
);

-- Keys Permissions: Link keys to permissions
CREATE TABLE `keys_permissions` (
	`temp_id` bigint AUTO_INCREMENT NOT NULL,
	`key_id` varchar(256) NOT NULL,
	`permission_id` varchar(256) NOT NULL,
	`workspace_id` varchar(256) NOT NULL,
	`created_at_m` bigint NOT NULL DEFAULT 0,
	`updated_at_m` bigint,
	CONSTRAINT `keys_permissions_key_id_permission_id_workspace_id` PRIMARY KEY(`key_id`,`permission_id`,`workspace_id`),
	CONSTRAINT `keys_permissions_temp_id_unique` UNIQUE(`temp_id`),
	CONSTRAINT `key_id_permission_id_idx` UNIQUE(`key_id`,`permission_id`)
);

-- Identities: Customer organizations/users
CREATE TABLE `identities` (
	`id` varchar(256) NOT NULL,
	`external_id` varchar(256) NOT NULL,
	`workspace_id` varchar(256) NOT NULL,
	`environment` varchar(256) NOT NULL DEFAULT 'default',
	`meta` json,
	`deleted` boolean NOT NULL DEFAULT false,
	`created_at` bigint NOT NULL,
	`updated_at` bigint,
	CONSTRAINT `identities_id` PRIMARY KEY(`id`),
	CONSTRAINT `workspace_id_external_id_deleted_idx` UNIQUE(`workspace_id`,`external_id`,`deleted`)
);

-- Rate Limits: Per-key or per-identity rate limits
CREATE TABLE `ratelimits` (
	`id` varchar(256) NOT NULL,
	`name` varchar(256) NOT NULL,
	`workspace_id` varchar(256) NOT NULL,
	`created_at` bigint NOT NULL,
	`updated_at` bigint,
	`key_id` varchar(256),
	`identity_id` varchar(256),
	`limit` int NOT NULL,
	`duration` bigint NOT NULL,
	`auto_apply` boolean NOT NULL DEFAULT false,
	CONSTRAINT `ratelimits_id` PRIMARY KEY(`id`),
	CONSTRAINT `unique_name_per_key_idx` UNIQUE(`key_id`,`name`),
	CONSTRAINT `unique_name_per_identity_idx` UNIQUE(`identity_id`,`name`)
);

-- Indexes for performance
CREATE INDEX `workspace_id_idx` ON `apis` (`workspace_id`);
CREATE INDEX `key_auth_id_deleted_at_idx` ON `keys` (`key_auth_id`,`deleted_at_m`);
CREATE INDEX `idx_keys_on_workspace_id` ON `keys` (`workspace_id`);
CREATE INDEX `owner_id_idx` ON `keys` (`owner_id`);
CREATE INDEX `identity_id_idx` ON `keys` (`identity_id`);
CREATE INDEX `deleted_at_idx` ON `keys` (`deleted_at_m`);
CREATE INDEX `name_idx` ON `ratelimits` (`name`);

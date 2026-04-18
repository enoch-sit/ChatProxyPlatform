// src/api/config.ts

const resolveApiBaseUrl = (): string => {
	const configuredUrl = import.meta.env.VITE_FLOWISE_PROXY_API_URL;
	if (configuredUrl) {
		return configuredUrl;
	}

	const host = window.location.hostname;
	const isLocalhost = host === 'localhost' || host === '127.0.0.1';

	// In AWS/remote deployments, use same-origin so ALB path-based routing handles API traffic.
	if (!isLocalhost) {
		return '';
	}

	return 'http://localhost:8000';
};

/**
 * Base URL for all API requests.
 * Priority:
 * 1) Explicit VITE_FLOWISE_PROXY_API_URL
 * 2) Same-origin for remote/browser deployments (e.g. AWS ALB path routing)
 * 3) localhost:8000 for local-only development
 */
export const API_BASE_URL = resolveApiBaseUrl();

/**
 * The default timeout for standard API requests, in milliseconds.
 */
export const API_TIMEOUT = 30000000;

/**
 * A long timeout specifically for streaming operations.
 * This is set to 30 minutes (1,800,000 ms) to accommodate chatflows
 * that may take a very long time to complete, preventing the connection
 * from closing prematurely.
 */
export const STREAM_TIMEOUT = 18000000;

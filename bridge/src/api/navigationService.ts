// src/api/navigationService.ts
// Provides imperative navigation outside the React tree (e.g. Zustand store, axios interceptor).
// Wire setNavigate() once at router mount via NavigateSetter in App.tsx.
import type { NavigateFunction } from 'react-router-dom';

let _navigate: NavigateFunction | null = null;

export function setNavigate(fn: NavigateFunction): void {
  _navigate = fn;
}

export function navigateTo(path: string): void {
  if (_navigate) {
    _navigate(path, { replace: true });
  } else {
    // Fallback before the router has mounted (e.g. very early logout)
    window.location.replace(path);
  }
}

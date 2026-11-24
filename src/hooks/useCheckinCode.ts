import { useState, useEffect, useRef, useCallback } from 'react';
import { supabase } from '../lib/supabase';

export interface CheckinCode {
  pin: string;
  qrCode: string;
  expiresAt: string;
  updatedAt: string;
}

interface DbCheckinCode {
  id: number;
  pin: string;
  qr_code: string;
  expires_at: string;
  updated_at: string;
}

const POLL_MS = 5000;
const CODE_TTL_MS = 5 * 60 * 1000;

function randomDigits(length: number): string {
  const values = new Uint32Array(length);
  crypto.getRandomValues(values);
  return Array.from(values, (value) => String(value % 10)).join('');
}

function randomToken(length: number): string {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  const values = new Uint32Array(length);
  crypto.getRandomValues(values);
  return Array.from(values, (value) => alphabet[value % alphabet.length]).join('');
}

export function getCheckinQrUrl(qrCode: string): string {
  const url = new URL(window.location.origin);
  url.searchParams.set('checkin', qrCode);
  return url.toString();
}

export function useCheckinCode() {
  const [code, setCode] = useState<CheckinCode | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const rotationRef = useRef<Promise<DbCheckinCode | null> | null>(null);

  const rotateCode = useCallback(async (): Promise<DbCheckinCode | null> => {
    if (rotationRef.current) return rotationRef.current;
    const request = (async () => {
      const expiresAt = new Date(Date.now() + CODE_TTL_MS).toISOString();
      const { data, error: err } = await supabase
        .from('checkin_codes')
        .upsert({
          id: 1,
          pin: randomDigits(4),
          qr_code: randomToken(12),
          expires_at: expiresAt,
          updated_at: new Date().toISOString(),
        }, { onConflict: 'id' })
        .select('id, pin, qr_code, expires_at, updated_at')
        .single();

      if (err) {
        console.error('[checkin_codes] rotation error:', err.message, err.code, err.details);
        throw err;
      }
      return data as DbCheckinCode;
    })();
    rotationRef.current = request;
    try {
      return await request;
    } finally {
      rotationRef.current = null;
    }
  }, []);

  const fetchCode = useCallback(async () => {
    try {
      const { data, error: err } = await supabase
        .from('checkin_codes')
        .select('id, pin, qr_code, expires_at, updated_at')
        .eq('id', 1)
        .maybeSingle();

      if (err) throw err;
      const row = data as DbCheckinCode | null;
      const freshRow = row && new Date(row.expires_at).getTime() > Date.now()
        ? row
        : await rotateCode();

      if (!freshRow) throw new Error('No hay código de check-in activo.');
      setCode({
        pin: freshRow.pin,
        qrCode: freshRow.qr_code,
        expiresAt: freshRow.expires_at,
        updatedAt: freshRow.updated_at,
      });
      setError(null);
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      console.error('[checkin_codes] fetch error:', err);
      setError(message);
    } finally {
      setLoading(false);
    }
  }, [rotateCode]);

  useEffect(() => {
    void fetchCode();
    timerRef.current = setInterval(() => void fetchCode(), POLL_MS);
    return () => {
      if (timerRef.current) clearInterval(timerRef.current);
    };
  }, [fetchCode]);

  return { code, loading, error, refresh: fetchCode };
}

export function useActiveCheckinCode(): {
  isValid: (input: string) => Promise<boolean>;
  loading: boolean;
} {
  const [loading, setLoading] = useState(false);

  const isValid = useCallback(async (input: string): Promise<boolean> => {
    const trimmed = input.trim();
    if (!trimmed) return false;

    setLoading(true);
    const { data, error } = await supabase
      .from('checkin_codes')
      .select('pin, qr_code, expires_at')
      .eq('id', 1)
      .maybeSingle();
    setLoading(false);

    if (error || !data) return false;
    const row = data as { pin: string; qr_code: string; expires_at: string };
    if (Date.now() > new Date(row.expires_at).getTime()) return false;

    let value = trimmed.toUpperCase();
    try {
      const url = new URL(trimmed);
      value = url.searchParams.get('checkin')?.toUpperCase() ?? value;
    } catch {
      // Input is a direct PIN or token.
    }
    return value === row.pin || value === row.qr_code.toUpperCase();
  }, []);

  return { isValid, loading };
}

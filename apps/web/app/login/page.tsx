'use client';
import { Auth } from '@supabase/auth-ui-react';
import { ThemeSupa } from '@supabase/auth-ui-shared';
import { supabaseBrowser } from '../../lib/supabase';   // ← Relative import (fixed)
import { useRouter } from 'next/navigation';
import { useEffect } from 'react';

export default function LoginPage() {
  const router = useRouter();

  useEffect(() => {
    const { data: { subscription } } = supabaseBrowser.auth.onAuthStateChange((event) => {
      if (event === 'SIGNED_IN') router.push('/dashboard');
    });
    return () => subscription.unsubscribe();
  }, [router]);

  return (
    <div className="min-h-screen flex items-center justify-center bg-zinc-950">
      <div className="w-full max-w-md p-8 bg-zinc-900 rounded-2xl border border-zinc-800">
        <div className="text-center mb-8">
          <h1 className="text-4xl font-bold tracking-tight">Parkitect</h1>
          <p className="text-zinc-400 mt-2">Parking Lot Intelligence Platform</p>
        </div>
        <Auth
          supabaseClient={supabaseBrowser}
          appearance={{ theme: ThemeSupa }}
          providers={['google', 'email']}
          redirectTo={`${window.location.origin}/dashboard`}
        />
      </div>
    </div>
  );
}

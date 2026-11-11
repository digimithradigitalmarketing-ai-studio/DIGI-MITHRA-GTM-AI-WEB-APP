// Shared result shapes for CRM forms and buttons. Kept in a plain module so both "use server"
// action files and client components can import the types.
export type CrmFormState = { error?: string; errors?: Record<string, string> };
export type CrmActionState = { ok?: boolean; message?: string; error?: string; redirectTo?: string } | null;

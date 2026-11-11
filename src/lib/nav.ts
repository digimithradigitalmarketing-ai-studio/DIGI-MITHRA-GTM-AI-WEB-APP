export type NavItem = {
  href: string;
  label: string;
};

// Route paths follow the build guide. Labels match the guide's module names.
export const NAV_ITEMS: NavItem[] = [
  { href: "/dashboard", label: "Dashboard" },
  { href: "/companies", label: "Companies" },
  { href: "/contacts", label: "Contacts" },
  { href: "/clients", label: "Clients" },
  { href: "/leads", label: "Leads" },
  { href: "/deals", label: "Deals" },
  { href: "/campaigns", label: "Campaigns" },
  { href: "/automations", label: "Automations" },
  { href: "/ai", label: "AI assistant" },
  { href: "/reports", label: "Reports" },
  { href: "/settings", label: "Settings" },
];

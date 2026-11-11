import { describe, expect, it } from "vitest";
import { likePattern, pageCount, pageRange, parseArchived, parsePage, pickAllowed, sanitizeSearch, PAGE_SIZE } from "./search";

describe("sanitizeSearch", () => {
  it("removes characters that change PostgREST filter syntax", () => {
    expect(sanitizeSearch("acme, inc) or (x")).toBe("acme inc or x");
  });
  it("collapses whitespace and caps the length", () => {
    expect(sanitizeSearch("  a    b  ")).toBe("a b");
    expect(sanitizeSearch("x".repeat(500))).toHaveLength(100);
  });
  it("returns empty for missing input", () => {
    expect(sanitizeSearch(undefined)).toBe("");
  });
});

describe("likePattern", () => {
  it("escapes LIKE wildcards so a literal % or _ matches itself", () => {
    expect(likePattern("50%_off")).toBe("%50\\%\\_off%");
    expect(likePattern("a\\b")).toBe("%a\\\\b%");
  });
});

describe("pagination", () => {
  it("parses page numbers and falls back to 1", () => {
    expect(parsePage("3")).toBe(3);
    expect(parsePage("-2")).toBe(1);
    expect(parsePage("abc")).toBe(1);
    expect(parsePage(undefined)).toBe(1);
    expect(parsePage("999999")).toBe(1000);
  });
  it("computes an inclusive range for a page", () => {
    expect(pageRange(1)).toEqual({ from: 0, to: PAGE_SIZE - 1 });
    expect(pageRange(3)).toEqual({ from: 40, to: 59 });
  });
  it("counts pages and never returns zero", () => {
    expect(pageCount(0)).toBe(1);
    expect(pageCount(20)).toBe(1);
    expect(pageCount(21)).toBe(2);
  });
});

describe("allow-lists", () => {
  it("accepts only listed values", () => {
    expect(pickAllowed("customer", ["prospect", "customer"] as const, "prospect")).toBe("customer");
    expect(pickAllowed("drop table", ["prospect", "customer"] as const, "prospect")).toBe("prospect");
  });
  it("defaults the archive filter to active", () => {
    expect(parseArchived("archived")).toBe("archived");
    expect(parseArchived("everything")).toBe("active");
  });
});

import { crmHref } from "./url";
describe("crmHref", () => {
  it("drops empty values and keeps the rest", () => {
    expect(crmHref("/companies", { workspace: "w1", q: "", page: 2, lifecycle: undefined })).toBe("/companies?workspace=w1&page=2");
  });
  it("omits only the default archive filter", () => {
    expect(crmHref("/clients", { workspace: "w1", archived: "active" })).toBe("/clients?workspace=w1");
    expect(crmHref("/clients", { workspace: "w1", archived: "all" })).toBe("/clients?workspace=w1&archived=all");
    expect(crmHref("/clients", { workspace: "w1", archived: "archived" })).toBe("/clients?workspace=w1&archived=archived");
  });
});

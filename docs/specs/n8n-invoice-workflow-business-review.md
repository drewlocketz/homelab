# Invoice Automation — Business Review

**Purpose:** We'd like your feedback on whether this workflow matches how invoices are actually handled today, and whether we're missing anything.

**What this is:** A plan to automate invoice processing. Instead of manually reading invoices, categorizing them, and entering them into QuickBooks, most of that would happen automatically. You'd just review and approve via text message.

---

## How It Would Work

### 1. Invoices arrive by email

Vendors send invoices (PDF or photo) to a dedicated email address (e.g. `ap@yourdomain.com`). This inbox is only for invoices — nothing else.

### 2. AI reads the invoice

The system automatically reads the invoice and pulls out:
- **Vendor name** (who sent it)
- **Invoice number**
- **Date** and **due date**
- **Total amount**
- **Line items** (what was purchased)
- **Expense category** (matched against your existing QuickBooks categories)

This works with both regular PDFs and photos/scans of paper invoices.

### 3. You get a text message for approval

You'll receive an SMS like:

> New invoice from **ACME Supplies**
> Amount: **$1,250.00**
> Date: 04/01/2026 / Due: 04/30/2026
> Category: **Office Supplies**
>
> Reply **YES** to approve, **NO** to reject

### 4a. If you reply YES

The expense is automatically logged in QuickBooks Online with:
- Vendor name
- Amount
- Date
- Category
- Invoice number as a reference

You get a confirmation text: *"Invoice from ACME Supplies for $1,250.00 logged in QuickBooks."*

### 4b. If you reply NO

The invoice is not logged. You get a confirmation text: *"Invoice from ACME Supplies rejected."*

You can then handle it manually if needed.

---

## What We Need From You

1. **Does this match your current process?** Are we missing any steps between receiving an invoice and logging it in QuickBooks?

2. **Expense categories** — Can you share the list of expense categories you currently use in QuickBooks? The AI needs this list to categorize invoices correctly.

3. **What information matters most?** Is the text message summary above (vendor, amount, date, due date, category) enough to make an approve/reject decision? Would you want to see anything else?

4. **Edge cases to consider:**
   - Do you ever receive invoices that need to be split across multiple categories?
   - Do invoices ever need to be assigned to a specific job or project?
   - Are there invoices that should be automatically approved (e.g. recurring monthly bills)?
   - Do you need to add notes or adjust the amount before approving?
   - What happens today if an invoice looks wrong or has a dispute?

5. **Volume** — Roughly how many invoices come in per week/month? (Helps us make sure the system can keep up.)

---

## What This Doesn't Cover (Yet)

These could be added later if useful:

- **Bill pay / scheduling payments** — this only logs the expense, it doesn't pay anything
- **Duplicate detection** — flagging if the same invoice number comes in twice
- **Monthly reports** — summarizing what was approved/rejected
- **Multiple approvers** — right now it goes to one phone number

---

*Please mark up, comment on, or reply to this document with any feedback. No detail is too small — if something doesn't match how things actually work, we want to know.*

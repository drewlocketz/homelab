# n8n Invoice Processing Workflow

## Executive Summary

Automate invoice processing for a small business (significant other's father). Invoices arrive via a dedicated Gmail inbox, an LLM (Claude) extracts key details and categorizes the expense, and an SMS is sent for approval. Upon approval the expense is logged in QuickBooks Online.

**Author:** Drew Locketz
**Date:** 2026-04-04
**Status:** Draft

---

## Dependencies

| Dependency | Why |
|---|---|
| `n8n.md` | n8n must be deployed and accessible |
| Dedicated email inbox (e.g. `ap@<domain>`) | Trigger source for incoming invoices |
| QuickBooks Online account | Destination for approved expenses |
| Twilio or SMS provider account | Sends approval requests via SMS |
| LLM API access (Claude or OpenAI) | Extracts and categorizes invoice data |

---

## Open Questions

- [ ] What are the existing QuickBooks expense categories? (needed to build the category mapping for the LLM prompt)

## Decided

- **Email**: Gmail (dedicated `ap@` inbox)
- **LLM**: Claude API (stronger vision for scanned invoices, reliable structured JSON output)
- **SMS**: Twilio

---

## Workflow

```
  ┌─────────────────────────────────────────────────────────────┐
  │                    n8n Workflow                              │
  │                                                             │
  │  1. EMAIL TRIGGER                                           │
  │  ┌──────────────┐                                           │
  │  │  IMAP/Gmail   │  Poll ap@... inbox for new emails        │
  │  │  Trigger      │  with attachments (PDF/image)            │
  │  └──────┬───────┘                                           │
  │         │                                                   │
  │  2. EXTRACT ATTACHMENT                                      │
  │  ┌──────▼───────┐                                           │
  │  │  Extract PDF  │  Pull invoice attachment from email      │
  │  │  / Image      │  Convert to text if needed               │
  │  └──────┬───────┘                                           │
  │         │                                                   │
  │  3. LLM ANALYSIS                                            │
  │  ┌──────▼───────┐                                           │
  │  │  LLM Node    │  Send invoice content to LLM with prompt: │
  │  │  (Claude/    │  - Extract: vendor, amount, date, due     │
  │  │   OpenAI)    │    date, invoice number, line items       │
  │  │              │  - Categorize against QB categories       │
  │  │              │  - Return structured JSON                 │
  │  └──────┬───────┘                                           │
  │         │                                                   │
  │  4. SEND APPROVAL SMS                                       │
  │  ┌──────▼───────┐                                           │
  │  │  SMS Node    │  Send summary to approver:                │
  │  │  (Twilio)    │  "Invoice from [vendor] for $[amount]     │
  │  │              │   Category: [category]                    │
  │  │              │   Reply YES to approve, NO to reject"     │
  │  └──────┬───────┘                                           │
  │         │                                                   │
  │  5. WAIT FOR REPLY                                          │
  │  ┌──────▼───────┐                                           │
  │  │  Webhook     │  Twilio forwards SMS reply to n8n         │
  │  │  (Twilio     │  webhook endpoint                         │
  │  │   callback)  │                                           │
  │  └──────┬───────┘                                           │
  │         │                                                   │
  │         ▼                                                   │
  │  ┌─────────────┐     ┌──────────────┐                       │
  │  │ YES approved │────▶│  6. LOG IN   │                       │
  │  └─────────────┘     │  QUICKBOOKS  │                       │
  │                      │  (Expense)   │                       │
  │  ┌─────────────┐     └──────────────┘                       │
  │  │ NO rejected  │────▶ Send confirmation SMS, archive email │
  │  └─────────────┘                                            │
  │                                                             │
  └─────────────────────────────────────────────────────────────┘
```

---

## Workflow Steps (Detail)

### Step 1: Email Trigger

- **Node**: IMAP Email Trigger (or Gmail Trigger if using Google)
- **Config**: Poll the `ap@` inbox on an interval (e.g. every 5 minutes)
- **Filter**: Only process emails with attachments (PDF, PNG, JPG)
- **Output**: Email metadata + attachment binary data

### Step 2: Extract Invoice Content

- **Node**: Extract from PDF / Read Binary Data
- **Logic**:
  - If PDF: extract text directly
  - If image (PNG/JPG): pass to LLM with vision capability for OCR
- **Output**: Raw invoice text or image data for LLM

### Step 3: LLM Analysis

- **Node**: Claude / OpenAI node
- **Prompt**: System prompt instructing the LLM to extract structured data from the invoice and categorize it against a provided list of QuickBooks categories
- **Expected output** (JSON):
  ```json
  {
    "vendor": "ACME Supplies",
    "invoice_number": "INV-2026-0412",
    "date": "2026-04-01",
    "due_date": "2026-04-30",
    "amount": 1250.00,
    "currency": "USD",
    "category": "Office Supplies",
    "line_items": [
      { "description": "Printer Paper (10 reams)", "amount": 250.00 },
      { "description": "Toner Cartridges (5)", "amount": 1000.00 }
    ],
    "confidence": "high",
    "notes": ""
  }
  ```
- **Category list**: Pulled from QuickBooks categories (TBD — see open questions)

### Step 4: Send Approval SMS

- **Node**: Twilio SMS
- **Message format**:
  ```
  New invoice from [vendor]
  Amount: $[amount]
  Date: [date] / Due: [due_date]
  Category: [category]
  
  Reply YES to approve, NO to reject
  ```
- **Store**: Save workflow execution ID + invoice data to n8n's internal storage for correlation with the reply

### Step 5: Wait for Approval Reply

- **Node**: Webhook (receives Twilio inbound SMS callback)
- **Logic**:
  - Match reply to pending invoice (by phone number + most recent pending)
  - Parse YES/NO response
  - Route to approval or rejection branch

### Step 6a: Approved — Log in QuickBooks

- **Node**: QuickBooks Online (HTTP Request or QB node)
- **Action**: Create Expense entry with:
  - Vendor name
  - Amount
  - Date
  - Category (mapped to QB account)
  - Invoice number in memo/reference field
- **Follow-up**: Send confirmation SMS ("Invoice from [vendor] for $[amount] logged in QuickBooks")

### Step 6b: Rejected — Archive

- **Action**: Send confirmation SMS ("Invoice from [vendor] rejected")
- **Optional**: Mark email as read / move to archive folder

---

## QuickBooks Integration

- **Auth**: OAuth 2.0 (configured in n8n credentials)
- **API**: QuickBooks Online REST API
- **Entity**: `Purchase` (expense) with:
  - `AccountRef`: mapped from LLM category → QB expense account
  - `EntityRef`: vendor (create if new, or match existing)
  - `TotalAmt`: invoice amount
  - `TxnDate`: invoice date
  - `DocNumber`: invoice number

---

## Security Considerations

- QuickBooks OAuth tokens stored in n8n's encrypted credential store
- Email credentials stored in n8n's encrypted credential store
- Twilio API keys stored in n8n's encrypted credential store
- LLM API key stored in n8n's encrypted credential store
- SMS approval is tied to a specific phone number (approver's) — no auth bypass
- Invoice data passes through the LLM API (consider data sensitivity)

---

## Tasks

### Manual Setup (before building the workflow)

- [ ] 1. Get QuickBooks expense category list from significant other's father
- [ ] 2. Create dedicated Gmail account for invoices (e.g. `ap@<domain>`)
- [ ] 3. Enable Gmail API access — create Google Cloud project, enable Gmail API, generate OAuth 2.0 credentials (or use App Password with IMAP)
- [ ] 4. Create Twilio account — get Account SID, Auth Token, and provision a phone number for SMS
- [ ] 5. Configure Twilio inbound SMS webhook URL to point to n8n (e.g. `https://n8n.home.drewdevlab.com/webhook/twilio-sms`)
- [ ] 6. Get Claude API key from Anthropic console
- [ ] 7. Set up QuickBooks Online OAuth app — register at developer.intuit.com, get Client ID + Client Secret, configure redirect URI to n8n's OAuth callback

### n8n Credential Configuration

- [ ] 8. Add Gmail credential in n8n (OAuth or IMAP with App Password)
- [ ] 9. Add Claude API credential in n8n
- [ ] 10. Add Twilio credential in n8n (Account SID + Auth Token)
- [ ] 11. Add QuickBooks Online credential in n8n (OAuth 2.0 — complete authorization flow)

### Workflow Build

- [ ] 12. Build email trigger + attachment extraction nodes
- [ ] 13. Build LLM analysis node with invoice extraction prompt + QB category list
- [ ] 14. Build Twilio SMS approval flow (send + webhook receive)
- [ ] 15. Build QuickBooks expense creation node
- [ ] 16. Build rejection/archive branch

### Testing

- [ ] 17. Test end-to-end with a sample PDF invoice
- [ ] 18. Test rejection flow (reply NO)
- [ ] 19. Test edge cases: no attachment, image-only invoice, multi-page PDF

---

## Success Criteria

- [ ] Email with PDF invoice triggers the workflow
- [ ] LLM correctly extracts vendor, amount, date, and category
- [ ] Owner receives SMS with invoice summary
- [ ] Replying YES creates the expense in QuickBooks
- [ ] Replying NO archives the invoice without logging
- [ ] Confirmation SMS sent after both approve and reject
- [ ] Image-based invoices (scans) are handled via LLM vision

-- Inofficial TRON Extension for MoneyMoney
-- Fetches balances from tronscan.org and returns them as securities
--
-- Username: 76cf8a94..., fdea5932...
-- Password: (anything)
--
-- Copyright (c) 2024 aaronk6
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.

WebBanking{
  version = 1.03,
  description = "Fetches balances from tronscan.org and returns them as securities",
  services = { "TRON" },
}

local currencyName = "TRON"
local currency = "EUR" -- fixme: Don't hardcode
local currencyField = "eur"
local currencyId = "tron"
local marketName = "CoinGecko"
local priceUrl = "https://api.coingecko.com/api/v3/simple/price?ids=" .. currencyId .. "&vs_currencies=" .. currencyField
local accountUrl = "https://apilist.tronscan.org/api/account?address="
local tokenUrl = "https://apilist.tronscan.org/api/token?showAll=1&id="
local tokenNames = {}

local addresses
local balances

function SupportsBank (protocol, bankCode)
  return protocol == ProtocolWebBanking and bankCode == "TRON"
end

function InitializeSession (protocol, bankCode, username, username2, password, username3)
  addresses = strsplit(",%s*", username)
end

function ListAccounts (knownAccounts)
  local account = {
    name = currencyName,
    accountNumber = currencyName,
    currency = currency,
    portfolio = true,
    type = "AccountTypePortfolio"
  }

  return {account}
end

function RefreshAccount (account, since)
  local s = {}
  local t
  local trx_price = queryPrices()[currencyField]
  local accounts = queryAccounts(addresses)
  local account

  for i,v in ipairs(addresses) do
    account = accounts[i]

    -- TRX
    s[#s+1] = createSecurity(account["address"], "TRX", "TRX", account["balance"], 6, trx_price)

    -- TRON Power (TP)
    s[#s+1] = createSecurity(account["address"], "TRON Power", "TP", calculateTronPower(account), 6, trx_price)

    -- TRC10 Tokens
    for key, token in pairs(accounts[i]["balances"]) do
      -- "_" is for TRX, we've already handled it above and can ignore it here.
      if token["name"] ~= "_" then
        t = resolveToken(token)
        if t then
          s[#s+1] = createSecurity(account["address"], t["name"], t["symbol"], t["balance"], t["decimals"], t["priceInTrx"] * trx_price)
        end
      end
    end
  end

  return {securities = s}
end

function EndSession ()
end

function resolveToken(token)
  local id = token["name"]

  -- return from cache
  if tokenNames[id] ~= nil then return tokenNames[id] end

  -- "_" is for TRX (not a token we can query)
  if id == "_" then return nil end

  -- ignore tokens that don't have a TRX price
  if not token["priceInTrx"] then return nil end

  local connection = Connection()
  local res = JSON(connection:request("GET", tokenUrl .. id)):dictionary()["data"][1]

  tokenNames[id] = {
    name = res["name"],
    symbol = res["abbr"],
    balance = token["balance"],
    priceInTrx = token["priceInTrx"],
    decimals = res["precision"]
  }

  return tokenNames[id]
end

function calculateTronPower(account)
  local balance = account["frozen"]["total"]

  -- The following is required to get the correct balance during the fixed frozen period (3 days after freezing).

  local ar = account["accountResource"]

  if ar["frozen_balance_for_energy"] and ar["frozen_balance_for_energy"]["frozen_balance"] then
    balance = balance + ar["frozen_balance_for_energy"]["frozen_balance"]
  end

  if ar["frozen_balance_for_bandwidth"] and ar["frozen_balance_for_bandwidth"]["frozen_balance"] then
    balance = balance + ar["frozen_balance_for_bandwidth"]["frozen_balance"]
  end

  return balance
end

function createSecurity(address, name, symbol, balance, decimals, price)

  local description = ""

  if symbol ~= name then
    description = " (" .. name .. ")"
  end

  return {
    name = symbol .. description .. " · " .. address,
    currency = nil,
    market = marketName,
    quantity = balance / (10 ^ decimals),
    price = price
  }
end

function queryPrices()
  local connection = Connection()
  local res = JSON(connection:request("GET", priceUrl))
  return res:dictionary()[currencyId]
end

function queryAccounts(addresses)
  local connection = Connection()
  local accounts = {}
  local res

  for key, address in pairs(addresses) do
    res = JSON(connection:request("GET", accountUrl .. address)):dictionary()
    table.insert(accounts, res)
  end

  return accounts
end

-- from http://lua-users.org/wiki/SplitJoin
function strsplit(delimiter, text)
  local list = {}
  local pos = 1
  if string.find("", delimiter, 1) then -- this would result in endless loops
    error("delimiter matches empty string!")
  end
  while 1 do
    local first, last = string.find(text, delimiter, pos)
    if first then -- found?
      table.insert(list, string.sub(text, pos, first-1))
      pos = last+1
    else
      table.insert(list, string.sub(text, pos))
      break
    end
  end
  return list
end

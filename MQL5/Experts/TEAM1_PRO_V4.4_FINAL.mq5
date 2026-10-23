{
   if(CopyBuffer(handle_fastMA,0,0,2,fastMA_buf)<=0) return false;
   if(CopyBuffer(handle_slowMA,0,0,2,slowMA_buf)<=0) return false;
   if(CopyBuffer(handle_rsi,0,0,1,rsi_buf)<=0) return false;
   if(CopyBuffer(handle_atr,0,0,1,atr_buf)<=0) return false;
   if(CopyBuffer(handle_adx,0,0,1,adx_buf)<=0) return false;
   if(CopyRates(_Symbol,PERIOD_CURRENT,0,1,rates)<=0) return false;
   fast=fastMA_buf[0]; slow=slowMA_buf[0]; rsi=rsi_buf[0]; atr=atr_buf[0]; adx=adx_buf[0]; price=rates[0].close;
   return true;
}

// FIX 1: DAILY EQUITY VS DRAWDOWN SEPARATED
bool EquityProtector()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if(dt.day!= last_day)
   {
      start_balance = AccountInfoDouble(ACCOUNT_BALANCE);
      start_equity = AccountInfoDouble(ACCOUNT_EQUITY); // Save start of day equity
      equity_peak = AccountInfoDouble(ACCOUNT_EQUITY);
      last_day = dt.day;
      martingale_step = 0;
   }
   double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double current_balance = AccountInfoDouble(ACCOUNT_BALANCE);

   double base_value = UseEquityForProtection? current_equity : current_balance;
   double base_start = UseEquityForProtection? start_equity : start_balance; // FIX: Use start_equity

   if(current_equity > equity_peak) equity_peak = current_equity;
   double daily_loss = (base_start - base_value) / base_start * 100.0; // Now correct
   double drawdown = (equity_peak - current_equity) / equity_peak * 100.0;

   if(daily_loss >= MaxDailyLossPercent || drawdown >= MaxTotalDrawdownPercent)
   {
      Comment("HALTED | Daily:",DoubleToString(daily_loss,2),"% DD:",DoubleToString(drawdown,2),"%");
      if(CloseAllOnHalt) CloseAllPositions();
      return false;
   }
   return true;
}

void CloseAllPositions(){
   for(int i=PositionsTotal()-1; i>=0; i--){
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionSelectByTicket(ticket))
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber){
            bool closed = trade.PositionClose(ticket);
            if(!closed) Print("CLOSE FAILED: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
         }
   }
}

void OnTradeTransaction(const MqlTradeTransaction& trans, const MqlTradeRequest& request, const MqlTradeResult& result)
{
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      if(HistoryDealSelect(trans.deal))
      {
         if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) == MagicNumber && HistoryDealGetString(trans.deal, DEAL_SYMBOL) == _Symbol && HistoryDealGetInteger(trans.deal, DEAL_ENTRY) == DEAL_ENTRY_OUT)
         {
            double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
            if(profit < 0 && UseMartingale && martingale_step < MaxMartingaleSteps) martingale_step++;
            else if(profit > 0) martingale_step = 0;
         }
      }
   }
}

bool CheckTradingHours(){ if(!UseTradingHours) return true; MqlDateTime dt; TimeToStruct(TimeCurrent(), dt); return (dt.hour >= StartHour && dt.hour < EndHour); }

// FIX 4: ROBUST CSV PARSER WITH QUOTES
bool IsNewsTime()
{
   if(!UseNewsFilter) return false;
   if(UseFFNewsCSV) return CheckFFNewsCSV();
   datetime server_time = TimeCurrent(); MqlDateTime dt;
   for(int i=0; i<ArraySize(news_hours); i++){ TimeToStruct(server_time, dt); dt.hour = news_hours[i]; dt.min = news_mins[i]; dt.sec = 0; datetime news_time = StructToTime(dt); double diff_minutes = MathAbs((server_time - news_time) / 60.0); if(diff_minutes <= MinutesBeforeNews) return true; }
   return false;
}

bool CheckFFNewsCSV()
{
   int file = FileOpen(NewsCSV_FileName, FILE_READ|FILE_TXT|FILE_COMMON); // Read as TXT
   if(file==INVALID_HANDLE) return false;
   datetime now = TimeCurrent();
   string line; FileReadString(file); // Skip header

   while(!FileIsEnding(file))
   {
      line = FileReadString(file);
      if(line == "") continue;
      string parts[];
      int count = StringSplit(line, ',', parts); // Split by comma
      if(count < 5) continue;

      string date_str = StringReplace((string)parts[0], "\"", "");
      string time_str = StringReplace((string)parts[1], "\"", "");
      string currency = StringReplace((string)parts[2], "\"", "");
      string impact = StringReplace((string)parts[3], "\"", "");

      if(FilterNewsByCurrency && currency!= base_currency && currency!= quote_currency) continue; // FIX 2

      datetime news_time = StringToTime(date_str + " " + time_str);
      if(impact == "High" && MathAbs(now - news_time) < MinutesBeforeNews * 60) {FileClose(file); return true;}
   }
   FileClose(file);
   return false;
}

bool CheckSpread(){ double spread_points = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / point_value; return (spread_points <= MaxSpreadPoints); }
bool IsMarketTrending(){ if(!UseSidewaysFilter) return true; double f,s,r,a,d,p; if(!GetIndicators(f,s,r,a,d,p)) return false; return!(d < ADXThreshold || a < MinATR); }

double CalculateLotSize(double sl_pips)
{
   double risk_amount = AccountInfoDouble(ACCOUNT_BALANCE) * RiskPercent / 100.0;
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_PROFIT);
   if(tick_value <= 0) tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double sl_in_price = sl_pips * pip_value;
   if(sl_in_price == 0 || tick_value == 0) return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lot = risk_amount / (sl_in_price / tick_size * tick_value);
   if(UseMartingale && martingale_step > 0) lot = lot * MathPow(MartingaleMultiplier, martingale_step);
   lot = MathFloor(lot / lot_step) * lot_step;
   return NormalizeDouble(MathMax(MathMin(lot, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX)), SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)), 2);
}

int CountOurPositions(){ int count=0; for(int i=0; i<PositionsTotal(); i++){ ulong ticket = PositionGetTicket(i); if(ticket > 0 && PositionSelectByTicket(ticket)) if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber) count++; } return count; }

bool CheckSignals(int &signal){ signal = 0; double fast,slow,rsi,atr,adx,price; if(!GetIndicators(fast,slow,rsi,atr,adx,price)) return false; double prev_fast=fastMA_buf[1]; double prev_slow=slowMA_buf[1]; bool ema_cross_up = prev_fast <= prev_slow && fast > slow && rsi > 50; bool ema_cross_dn = prev_fast >= prev_slow && fast < slow && rsi < 50; if(ema_cross_up) signal = 1; if(ema_cross_dn) signal = -1; if(UseDipRip){ double dip_level = slow - atr * DipMultiplier; double rip_level = slow + atr * RipMultiplier; if(price <= dip_level && rsi < RSIDip) signal = 1; if(price >= rip_level && rsi > RSIRip) signal = -1; } return (signal!= 0); }

void OpenTrade(int signal)
{
   if(TradeOnlyOne && CountOurPositions() > 0) return;
   if(TimeCurrent() - last_trade_time < CooldownMinutes * 60) return;
   double lot = CalculateLotSize(StopLossPips);
   double sl_price = NormalizeDouble(StopLossPips * pip_value, _Digits);
   double tp_price = NormalizeDouble(TakeProfitPips * pip_value, _Digits);
   bool result = false;
   if(signal == 1){ double price = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK), _Digits); result = trade.Buy(lot, _Symbol, price, price - sl_price, price + tp_price, "TT4.4_Buy_S"+IntegerToString(martingale_step)); }
   else if(signal == -1){ double price = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits); result = trade.Sell(lot, _Symbol, price, price + sl_price, price - tp_price, "TT4.4_Sell_S"+IntegerToString(martingale_step)); }
   if(result) last_trade_time = TimeCurrent(); else Print("ORDER FAILED: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
}

// FIX 3: NORMALIZE TP ON MODIFY
void ManageTrades()
{
   for(int i=0; i<PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         {
            double price_open = PositionGetDouble(POSITION_PRICE_OPEN);
            double price_current = PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            double profit_pips = MathAbs(price_current - price_open) / pip_value;
            double sl = PositionGetDouble(POSITION_SL); double tp = NormalizeDouble(PositionGetDouble(POSITION_TP), _Digits); int type = (int)PositionGetInteger(POSITION_TYPE); double new_sl = 0; // FIX 3

            if(profit_pips >= BreakEven) new_sl = NormalizeDouble(price_open, _Digits);
            if(profit_pips >= TrailStart) new_sl = NormalizeDouble(type == POSITION_TYPE_BUY? price_current - TrailStep * pip_value : price_current + TrailStep * pip_value, _Digits);

            if(new_sl > 0)
            {
               double distance = MathAbs(price_current - new_sl);
               if(distance > stops_level && distance > freeze_level)
               {
                  bool mod_result = false;
                  if(type == POSITION_TYPE_BUY && new_sl > sl) mod_result = trade.PositionModify(ticket, new_sl, tp);
                  if(type == POSITION_TYPE_SELL && new_sl < sl) mod_result = trade.PositionModify(ticket, new_sl, tp);
                  if(!mod_result) Print("MODIFY FAILED: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
               }
            }
         }
      }
   }
}

void OnTick()
{
   if(!EquityProtector()) {Comment("BOT HALTED"); return;}
   if(!CheckTradingHours()) {Comment("Outside Hours"); return;}
   if(IsNewsTime()) {Comment("News Pause"); return;}
   if(!CheckSpread()) {Comment("High Spread"); return;}
   if(!IsMarketTrending()) {Comment("Sideways Market"); return;}
   ManageTrades();
   int signal;
   if(CheckSignals(signal)) OpenTrade(signal);
}
//+------------------------------------------------------------------+

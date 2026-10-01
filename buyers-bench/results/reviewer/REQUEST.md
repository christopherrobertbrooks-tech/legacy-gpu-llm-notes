I want a small system to run my Etsy shop's inventory and orders from the command
line. It's three pieces, and three different people will build them at the same
time without seeing each other's code:

  1. catalog.py -- my listings: SKU, title, price, and how many I have in stock.
  2. orders.py  -- placing an order for some quantity of a listing, refunding an
                   order, and working out the money, including Etsy's cut.
  3. shop.py    -- the command-line tool I actually run, which uses the other two.

The commands I want:

    python3 shop.py add SKU "Some Title" PRICE STOCK
    python3 shop.py order SKU QTY
    python3 shop.py refund ORDER_ID
    python3 shop.py stock SKU
    python3 shop.py report

Placing an order should tell me its order ID so I can refund it later. Keep all the
data in files next to the scripts so it's there next time. Etsy takes a cut of every
sale, so the report needs to show what buyers paid and what I actually keep.

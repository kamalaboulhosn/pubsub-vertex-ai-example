package data_generator;

import com.google.api.core.ApiFuture;
import com.google.api.core.ApiFutureCallback;
import com.google.api.core.ApiFutures;
import com.google.cloud.pubsub.v1.Publisher;
import com.google.common.util.concurrent.MoreExecutors;
import com.google.gson.Gson;
import com.google.protobuf.ByteString;
import com.google.pubsub.v1.ProjectTopicName;
import com.google.pubsub.v1.PubsubMessage;

import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.LinkedHashMap; // Added to maintain order for fraud scenarios
import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.concurrent.TimeUnit;

/**
 * Generates simulated credit card transactions and publishes them to Google
 * Cloud Pub/Sub with an ordering key.
 *
 * * Note: This code assumes the Pub/Sub topic has message ordering enabled.
 * * Usage: java TransactionGenerator <PROJECT_ID> <REGION>
 */
public class TransactionGenerator {

  // --- Configuration Constants ---

  private static final String TOPIC_ID = "fraud-example-transactions";

  // Fraud Injection Rules (Now based on multi-step scenarios)
  // 2.0% chance that a multi-step fraud sequence (2 or 3 transactions) is triggered
  private static final double FRAUD_SCENARIO_PROBABILITY = 0.02;
  private static final long FRAUD_SHORT_DELAY_MS = 4000L; // 4 seconds delay between steps in a scenario

  private static final double FRAUD_MIN_AMOUNT = 2000.0;
  private static final double FRAUD_MAX_AMOUNT = 7000.0;

  // IP/Ordering Key Stickiness Rules
  private static final double IP_CHANGE_PROBABILITY = 0.005; // 0.5% chance that the "home" IP changes

  // Time Simulation Rules
  private static final long MIN_TIME_INCREMENT_MS = 1000L; // 1 second
  private static final long MAX_TIME_INCREMENT_MS = 3600000L; // 1 hour

  // --- Static Utility & Data Generators ---

  // Static utility for serialization
  private static final Gson GSON = new Gson();

  // Thread-safe random number generator
  private static final Random RANDOM = new Random();

  // Simulated Global Clock (as epoch milliseconds). Initialized to a time in the past.
  private static long simulatedCurrentTime = System.currentTimeMillis() - (125400L * 60 * 1000);

  // Map to store the "home" IP for each credit card (maintaining sticky IPs)
  private static final Map<String, String> cardIpMap = new HashMap<>();

  // Programmatically generated list of fake credit card numbers
  private static final List<String> CARD_NUMBERS = generateCardNumbers(10000);

  // Static list of all receivers (Collections.unmodifiableList added for immutability)
  private static final List<String> ALL_RECEIVERS = Collections.unmodifiableList(Arrays.asList(
      // Retail (General)
      "Walmart", "Target", "Costco Wholesale", "Kmart", "Meijer", "Kroger", "Publix", "Safeway",
      "Albertsons", "Whole Foods Market", "Trader Joe's", "Aldi", "Lidl", "Wegmans", "H-E-B",
      "Stop & Shop", "Giant Food", "Food Lion", "Winn-Dixie", "Piggly Wiggly", "Sprouts Farmers Market",

      // Retail (Hardware/Home)
      "The Home Depot", "Lowe's", "Ace Hardware", "True Value", "Menards", "Harbor Freight Tools",
      "Tractor Supply Co.", "Bed Bath & Beyond", "IKEA", "Crate & Barrel", "Williams-Sonoma",
      "Pottery Barn", "Restoration Hardware", "At Home", "Floor & Decor",

      // Retail (Electronics/Office) - HIGH VALUE FRAUD TARGETS
      "Best Buy", "Micro Center", "Apple Store", "Microsoft Store", "GameStop", "Staples",
      "Office Depot", "OfficeMax", "CDW", "Newegg.com",

      // Retail (Apparel)
      "Macy's", "Nordstrom", "Dillard's", "Kohl's", "JCPenney", "Saks Fifth Avenue", "Neiman Marcus",
      "Bloomingdale's", "Gap", "Old Navy", "Banana Republic", "J.Crew", "H&M", "Zara", "Uniqlo",
      "Forever 21", "American Eagle Outfitters", "Abercrombie & Fitch", "Hollister Co.", "Lululemon",
      "Nike", "Adidas", "Puma", "Under Armour", "Reebok", "Dick's Sporting Goods", "Academy Sports + Outdoors",
      "REI", "Cabela's", "Bass Pro Shops", "Foot Locker", "Victoria's Secret", "Bath & Body Works",
      "The Children's Place", "Carter's",

      // Retail (Pharmacies)
      "CVS Pharmacy", "Walgreens", "Rite Aid", "GoodRx",

      // Retail (Discount)
      "Dollar General", "Dollar Tree", "Family Dollar", "Five Below", "Big Lots", "Ollie's Bargain Outlet",

      // Retail (Online) - HIGH VALUE FRAUD TARGETS
      "Amazon.com", "eBay", "Etsy", "Wayfair", "Overstock.com", "Zappos", "Chewy", "Wish.com",

      // Restaurants (Fast Food)
      "McDonald's", "Burger King", "Wendy's", "Taco Bell", "Chick-fil-A", "Subway", "KFC",
      "Popeyes", "Arby's", "Jack in the Box", "Sonic Drive-In", "Whataburger", "In-N-Out Burger",
      "Five Guys", "Shake Shack", "Pizza Hut", "Domino's", "Papa John's", "Little Caesars",
      "Panda Express", "Chipotle Mexican Grill", "Qdoba", "Moe's Southwest Grill", "Del Taco",

      // Restaurants (Casual/Coffee)
      "Starbucks", "Dunkin'", "Panera Bread", "Tim Hortons", "Peet's Coffee", "The Coffee Bean & Tea Leaf",
      "Applebee's", "Chili's Grill & Bar", "TGI Fridays", "Olive Garden", "Red Lobster", "Outback Steakhouse",
      "Texas Roadhouse", "LongHorn Steakhouse", "The Cheesecake Factory", "Red Robin", "Buffalo Wild Wings",
      "Denny's", "IHOP", "Cracker Barrel", "Waffle House", "P.F. Chang's",

      // Tech & Services
      "Google", "Microsoft", "Apple Inc.", "Meta Platforms", "Amazon Web Services", "Netflix", "Spotify",
      "Hulu", "Disney+", "Salesforce", "Oracle", "IBM", "Intel", "AMD", "Nvidia", "Dell Technologies",
      "HP Inc.", "Cisco Systems", "Adobe", "Zoom Video", "Uber", "Lyft", "DoorDash", "Grubhub",
      "Instacart", "Airbnb", "PayPal", "Block (Square)", "Stripe", "Shopify", "GoDaddy", "Intuit",
      "Dropbox", "Slack", "X (Twitter)",

      // Travel & Auto
      "Delta Air Lines", "American Airlines", "United Airlines", "Southwest Airlines", "JetBlue",
      "Alaska Airlines", "Spirit Airlines", "Frontier Airlines", "Marriott International", "Hilton",
      "Hyatt Hotels", "IHG Hotels & Resorts", "Wyndham Hotels", "Choice Hotels", "Best Western",
      "Expedia", "Booking.com", "Enterprise Rent-A-Car", "Hertz", "Avis", "Budget", "AutoZone",
      "O'Reilly Auto Parts", "Advance Auto Parts", "NAPA Auto Parts", "Pep Boys",

      // Charities & Non-Profits - FRAUD DRIP TARGETS
      "American Red Cross", "Doctors Without Borders", "UNICEF", "Habitat for Humanity",
      "St. Jude Children's Research Hospital", "The Humane Society", "WWF (World Wildlife Fund)",
      "Sierra Club", "The Nature Conservancy", "Feeding America", "Goodwill Industries",
      "The Salvation Army", "United Way", "Boys & Girls Clubs of America", "Make-A-Wish Foundation",
      "Susan G. Komen", "American Cancer Society", "American Heart Association", "Save the Children",
      "Shriners Hospitals for Children", "Wounded Warrior Project", "ASPCA", "Charity: Water",

      // Utilities & Telecom
      "AT&T", "Verizon", "T-Mobile", "Comcast (Xfinity)", "Charter (Spectrum)", "Cox Communications",
      "Duke Energy", "NextEra Energy", "Southern Company", "Dominion Energy", "Exelon",
      "Pacific Gas and Electric (PG&E)", "Con Edison",

      // Finance & Insurance
      "Bank of America", "JPMorgan Chase", "Wells Fargo", "Citigroup", "Goldman Sachs", "Morgan Stanley",
      "U.S. Bank", "PNC", "Capital One", "American Express", "Visa", "Mastercard", "Discover",
      "Geico", "Progressive", "State Farm", "Allstate", "Liberty Mutual",

      // Miscellaneous
      "7-Eleven", "Circle K", "Shell", "ExxonMobil", "BP", "Chevron", "Marathon Petroleum",
      "Sheetz", "Wawa", "The LEGO Group", "Mattel", "Hasbro", "The Walt Disney Company",
      "Paramount", "Warner Bros.", "Sony Pictures", "Universal Pictures")
  );

  // Filtered lists for specific fraud scenarios
  private static final List<String> CHARITY_RECEIVERS = Collections.unmodifiableList(Arrays.asList(
      "American Red Cross", "Doctors Without Borders", "UNICEF", "Habitat for Humanity",
      "St. Jude Children's Research Hospital", "The Humane Society", "WWF (World Wildlife Fund)",
      "Sierra Club", "The Nature Conservancy", "Feeding America", "Goodwill Industries",
      "The Salvation Army", "United Way", "Boys & Girls Clubs of America", "Make-A-Wish Foundation",
      "Susan G. Komen", "American Cancer Society", "American Heart Association", "Save the Children",
      "Shriners Hospitals for Children", "Wounded Warrior Project", "ASPCA", "Charity: Water"
  ));

  private static final List<String> HIGH_VALUE_FRAUD_TARGETS = Collections.unmodifiableList(Arrays.asList(
      // Retail (Electronics/Office)
      "Best Buy", "Micro Center", "Apple Store", "Microsoft Store", "GameStop", "Staples",
      "Office Depot", "OfficeMax", "CDW", "Newegg.com",
      // Retail (Online)
      "Amazon.com", "eBay", "Etsy", "Wayfair", "Overstock.com", "Zappos", "Chewy", "Wish.com"
  ));


  /**
   * POJO for the transaction event. Fields must exactly match the BigQuery schema.
   * The 'source' attribute has been removed to align with BigQuery's schema.
   */
  static class TransactionEvent {
    // Field names must exactly match the BigQuery schema columns (e.g., credit_card_number)
    String credit_card_number;
    String receiver;
    double amount;
    String ip_address;
    String timestamp;

    public TransactionEvent(String creditCardNumber, String receiver, double amount, String ipAddress,
        long epochMilli) {
      this.credit_card_number = creditCardNumber;
      this.receiver = receiver;
      this.amount = amount;
      this.ip_address = ipAddress;
      // Format Epoch Milliseconds to BQ DATETIME string
      Instant instant = Instant.ofEpochMilli(epochMilli);
      LocalDateTime ldt = LocalDateTime.ofInstant(instant, ZoneOffset.UTC);
      this.timestamp = ldt.format(DateTimeFormatter.ISO_LOCAL_DATE_TIME);
    }
  }

  // --- Static Utility Methods ---

  /**
   * Programmatically generates a list of fake credit card numbers.
   */
  private static List<String> generateCardNumbers(int count) {
    List<String> cardNumbers = new ArrayList<>(count);
    for (int i = 0; i < count; i++) {
      // 40% Visa-like, 40% Mastercard-like, 20% Amex-like
      int type = RANDOM.nextInt(10);
      if (type < 4) {
        // Visa-like (16 digits, starting with 4)
        cardNumbers.add("4200" + generateRandomDigits(12));
      } else if (type < 8) {
        // Mastercard-like (16 digits, starting with 5)
        cardNumbers.add("5500" + generateRandomDigits(12));
      } else {
        // Amex-like (15 digits, starting with 3)
        cardNumbers.add("3700" + generateRandomDigits(11));
      }
    }
    System.out.println("Generated " + cardNumbers.size() + " card numbers.");
    return cardNumbers;
  }

  /**
   * Generates a random string of digits of a given length.
   */
  private static String generateRandomDigits(int length) {
    StringBuilder sb = new StringBuilder(length);
    for (int i = 0; i < length; i++) {
      sb.append(RANDOM.nextInt(10));
    }
    return sb.toString();
  }

  private static String getRandomCardNumber() {
    return CARD_NUMBERS.get(RANDOM.nextInt(CARD_NUMBERS.size()));
  }

  private static String getRandomReceiver() {
    // For general transactions, use the full list
    return ALL_RECEIVERS.get(RANDOM.nextInt(ALL_RECEIVERS.size()));
  }

  private static String getCharityReceiver() {
    // For Scenario 1 drip transaction
    return CHARITY_RECEIVERS.get(RANDOM.nextInt(CHARITY_RECEIVERS.size()));
  }

  private static String getFraudTargetReceiver() {
    // For high-value fraud transaction
    return HIGH_VALUE_FRAUD_TARGETS.get(RANDOM.nextInt(HIGH_VALUE_FRAUD_TARGETS.size()));
  }

  private static double getRandomAmount() {
    // Random amount between $1.00 and $500.00 (Normal transaction range)
    double amount = 1.0 + (500.0 - 1.0) * RANDOM.nextDouble();
    // Round to two decimal places
    return Math.round(amount * 100.0) / 100.0;
  }

  private static double getRandomFraudAmount() {
    // Random amount between FRAUD_MIN_AMOUNT and FRAUD_MAX_AMOUNT (High value)
    double amount = FRAUD_MIN_AMOUNT + (FRAUD_MAX_AMOUNT - FRAUD_MIN_AMOUNT) * RANDOM.nextDouble();
    // Round to two decimal places
    return Math.round(amount * 100.0) / 100.0;
  }

  /** Generates a new random IPv4 address. */
  private static String generateNewRandomIp() {
    return RANDOM.nextInt(256) + "." + RANDOM.nextInt(256) + "." +
        RANDOM.nextInt(256) + "." + RANDOM.nextInt(256);
  }

  /**
   * Retrieves the current IP address for a card, applying stickiness and
   * a small chance of change.
   */
  private static String getIpForCard(String cardNumber) {
    if (!cardIpMap.containsKey(cardNumber)) {
      // If new card, assign a "home" IP
      String homeIp = generateNewRandomIp();
      cardIpMap.put(cardNumber, homeIp);
      return homeIp;
    } else {
      // Small chance to change the IP (simulate travel/new network)
      if (RANDOM.nextDouble() < IP_CHANGE_PROBABILITY) {
        String newIp = generateNewRandomIp();
        cardIpMap.put(cardNumber, newIp);
        return newIp;
      } else {
        // Return the existing "home" IP
        return cardIpMap.get(cardNumber);
      }
    }
  }

  /**
   * Publishes a single transaction event to Pub/Sub.
   * The sourceTag is used only for console logging, not included in the payload.
   */
  private static void publishMessage(Publisher publisher, TransactionEvent event, String sourceTag) {
    // Log based on source/type
    if (sourceTag.contains("FRAUD")) {
      String cardSuffix = event.credit_card_number.substring(event.credit_card_number.length() - 4);
      System.out.printf(">>> [Card: ...%s, %s, IP: %s, Amt: $%.2f, Time: %s, Source: %s]%n",
          cardSuffix, event.receiver, event.ip_address, event.amount, event.timestamp, sourceTag);
    }

    String jsonMessage = GSON.toJson(event);

    // 1. Build the message with data and ordering key (card number)
    ByteString data = ByteString.copyFromUtf8(jsonMessage);
    PubsubMessage pubsubMessage = PubsubMessage.newBuilder()
        .setData(data)
        .setOrderingKey(event.credit_card_number) // Key is the card number for ordered processing
        .build();

    // 2. Publish asynchronously
    ApiFuture<String> future = publisher.publish(pubsubMessage);

    // 3. Add a callback to log failure
    ApiFutures.addCallback(future, new ApiFutureCallback<String>() {
      @Override
      public void onFailure(Throwable t) {
        System.err.println(" -> Error publishing message: " + t.getMessage());
      }

      @Override
      public void onSuccess(String messageId) {
        // Commented out for cleaner output
        // System.out.println(" -> Published message with ID: " + messageId);
      }
    }, MoreExecutors.directExecutor());
  }

  // --- Main Execution ---

  public static void main(String[] args) throws Exception {

    // --- 1. Parse Command Line Arguments ---
    if (args.length < 2) {
      System.err.println("Error: PROJECT_ID and REGION must be provided as command-line arguments.");
      System.err.println("Usage: java TransactionGenerator <PROJECT_ID> <REGION>");
      System.exit(1);
    }

    final String projectId = args[0];
    final String region = args[1];

    final String endpoint = region + "-pubsub.googleapis.com:443";
    ProjectTopicName topicName = ProjectTopicName.of(projectId, TOPIC_ID);
    Publisher publisher = null;

    try {
      // Initialize Publisher with Ordering and Endpoint
      publisher = Publisher.newBuilder(topicName)
          .setEnableMessageOrdering(true)
          .setEndpoint(endpoint) // Use the derived endpoint
          .build();

      System.out.println("Starting transaction generation for topic: " + topicName);
      System.out.println("Using endpoint: " + endpoint);
      System.out.println("Using static list of " + ALL_RECEIVERS.size() + " real receivers.");
      System.out.printf("Injecting multi-step fraud sequences with %.3f%% probability.%n",
          FRAUD_SCENARIO_PROBABILITY * 100);
      System.out.println("Press Ctrl+C to stop.");

      while (true) {
        // Use a LinkedHashMap to hold the events and their corresponding source tags for logging/debugging
        Map<TransactionEvent, String> eventsToPublish = new LinkedHashMap<>();
        String cardNumber;

        // --- 0. Advance the simulated clock normally (This time is the base time for the next transaction) ---
        long incrementRange = MAX_TIME_INCREMENT_MS - MIN_TIME_INCREMENT_MS + 1;
        long timeIncrement = MIN_TIME_INCREMENT_MS + RANDOM.nextInt((int) incrementRange);
        simulatedCurrentTime += timeIncrement;

        if (RANDOM.nextDouble() < FRAUD_SCENARIO_PROBABILITY) {
          // --- INJECTING MULTI-STEP FRAUD SCENARIO ---
          cardNumber = getRandomCardNumber();
          String fraudIp = generateNewRandomIp(); // New, non-sticky IP for the compromised activity

          // Ensure the card's "home" IP is set for the normal path, even if we use a new one now.
          getIpForCard(cardNumber);

          if (RANDOM.nextBoolean()) {
            // --- Scenario 1: Charity Drip -> Large Purchase (2 steps) ---

            // Step 1: Small Charity Transaction (Drip)
            long step1Time = simulatedCurrentTime;
            TransactionEvent step1 = new TransactionEvent(
                cardNumber,
                getCharityReceiver(),
                getRandomAmount(), // Small value, blending in
                fraudIp,
                step1Time
            );
            eventsToPublish.put(step1, "FRAUD_SCENARIO_1_CHARITY_DRIP");

            // Step 2: Large High-Value Purchase (Exploitation)
            long step2Time = step1Time + FRAUD_SHORT_DELAY_MS;
            TransactionEvent step2 = new TransactionEvent(
                cardNumber,
                getFraudTargetReceiver(),
                getRandomFraudAmount(), // High value, target category
                fraudIp,
                step2Time
            );
            eventsToPublish.put(step2, "FRAUD_SCENARIO_1_LARGE_PURCHASE");

            // Advance the simulated clock by the time passed in the sequence for the next iteration
            simulatedCurrentTime = step2Time;

          } else {
            // --- Scenario 2: Two Small Drips -> Large Purchase (3 steps) ---

            // Step 1: Small Transaction 1 (Micro-Drip 1)
            long step1Time = simulatedCurrentTime;
            TransactionEvent step1 = new TransactionEvent(
                cardNumber,
                getRandomReceiver(), // General receiver
                getRandomAmount(),
                fraudIp,
                step1Time
            );
            eventsToPublish.put(step1, "FRAUD_SCENARIO_2_MICRO_DRIP_1");

            // Step 2: Small Transaction 2 (Micro-Drip 2)
            long step2Time = step1Time + FRAUD_SHORT_DELAY_MS;
            TransactionEvent step2 = new TransactionEvent(
                cardNumber,
                getRandomReceiver(), // General receiver
                getRandomAmount(),
                fraudIp,
                step2Time
            );
            eventsToPublish.put(step2, "FRAUD_SCENARIO_2_MICRO_DRIP_2");

            // Step 3: Large High-Value Purchase (Exploitation)
            long step3Time = step2Time + FRAUD_SHORT_DELAY_MS;
            TransactionEvent step3 = new TransactionEvent(
                cardNumber,
                getFraudTargetReceiver(),
                getRandomFraudAmount(), // High value, target category
                fraudIp,
                step3Time
            );
            eventsToPublish.put(step3, "FRAUD_SCENARIO_2_LARGE_PURCHASE");

            // Advance the simulated clock by the time passed in the sequence for the next iteration
            simulatedCurrentTime = step3Time;
          }

        } else {
          // --- GENERATE SINGLE NORMAL TRANSACTION (Default path) ---
          cardNumber = getRandomCardNumber();
          String receiver = getRandomReceiver();
          double amount = getRandomAmount();
          String ipAddress = getIpForCard(cardNumber); // Use "sticky" IP logic

          // Create the single normal event
          TransactionEvent normalEvent = new TransactionEvent(
              cardNumber, receiver, amount, ipAddress, simulatedCurrentTime
          );
          eventsToPublish.put(normalEvent, "NORMAL");
        }


        // --- Publish ALL Messages for this iteration/scenario ---
        for (Map.Entry<TransactionEvent, String> entry : eventsToPublish.entrySet()) {
          publishMessage(publisher, entry.getKey(), entry.getValue());
        }

        // 7. Wait for 1 second (real time) before publishing the next event
        // This controls the rate at which batches of events (1 normal or 2/3 fraud) are sent.
        Thread.sleep(1000);
      }
    } catch (InterruptedException e) {
      System.out.println("Transaction generator interrupted. Shutting down.");
      Thread.currentThread().interrupt(); // Restore the interrupted status
    } catch (Exception e) {
      System.err.println("An error occurred: " + e.getMessage());
      e.printStackTrace();
    } finally {
      // 8. Shut down the publisher gracefully
      if (publisher != null) {
        System.out.println("Shutting down publisher...");
        publisher.shutdown();
        publisher.awaitTermination(1, TimeUnit.MINUTES);
        System.out.println("Publisher shut down.");
      }
    }
  }
}
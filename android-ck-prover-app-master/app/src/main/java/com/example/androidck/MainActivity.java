package com.example.androidck;

import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.res.AssetManager;
import android.os.Bundle;
import android.os.Looper;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyInfo;
import android.security.keystore.KeyProperties;
import android.text.method.ScrollingMovementMethod;
import android.util.Base64;
import android.util.Log;
import android.widget.Button;
import android.widget.EditText;
import android.widget.TextView;
import android.widget.Toast;

import androidx.appcompat.app.AppCompatActivity;

import com.google.android.gms.tasks.OnSuccessListener;
import com.google.android.gms.tasks.Task;
import com.google.android.play.core.integrity.IntegrityManager;
import com.google.android.play.core.integrity.IntegrityManagerFactory;
import com.google.android.play.core.integrity.IntegrityTokenRequest;
import com.google.android.play.core.integrity.IntegrityTokenResponse;
import com.google.api.client.googleapis.services.GoogleClientRequestInitializer;
import com.google.api.client.http.HttpRequestInitializer;
import com.google.api.client.http.HttpTransport;
import com.google.api.client.http.javanet.NetHttpTransport;
import com.google.api.client.json.JsonFactory;
import com.google.api.client.json.jackson2.JacksonFactory;
import com.google.api.services.playintegrity.v1.PlayIntegrity;
import com.google.api.services.playintegrity.v1.PlayIntegrityRequestInitializer;
import com.google.api.services.playintegrity.v1.PlayIntegrityScopes;
import com.google.api.services.playintegrity.v1.model.DecodeIntegrityTokenRequest;
import com.google.api.services.playintegrity.v1.model.DecodeIntegrityTokenResponse;
import com.google.api.services.playintegrity.v1.model.TokenPayloadExternal;
import com.google.auth.http.HttpCredentialsAdapter;
import com.google.auth.oauth2.GoogleCredentials;

import org.bouncycastle.asn1.ASN1Encodable;
import org.bouncycastle.asn1.ASN1InputStream;
import org.bouncycastle.asn1.ASN1Object;
import org.bouncycastle.asn1.ASN1OctetString;
import org.bouncycastle.asn1.ASN1Primitive;
import org.bouncycastle.asn1.ASN1Sequence;
import org.bouncycastle.asn1.ASN1TaggedObject;
import org.bouncycastle.asn1.util.ASN1Dump;
import org.web3j.crypto.Credentials;
import org.web3j.crypto.Keys;
import org.web3j.crypto.Sign;
import org.web3j.utils.Numeric;

import java.io.IOException;
import java.io.InputStream;
import java.io.UnsupportedEncodingException;
import java.nio.charset.StandardCharsets;
import java.security.InvalidAlgorithmParameterException;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.KeyStore;
import java.security.KeyStoreException;
import java.security.NoSuchAlgorithmException;
import java.security.NoSuchProviderException;
import java.security.cert.Certificate;
import java.security.cert.CertificateEncodingException;
import java.security.cert.CertificateException;
import java.security.cert.X509Certificate;
import java.security.spec.ECGenParameterSpec;
import java.util.Arrays;
import java.util.Calendar;
import java.util.HashMap;
import java.util.Map;
import java.util.Random;
import java.util.stream.Collectors;

import javax.crypto.SecretKeyFactory;

public class MainActivity extends AppCompatActivity {

    private String getKeystore(byte[] challenge) throws KeyStoreException, IOException, NoSuchAlgorithmException, NoSuchProviderException, InvalidAlgorithmParameterException, CertificateException {
        // Create KeyPairGenerator and set generation parameters for an ECDSA key pair
        // using the NIST P-256 curve.  "Key1" is the key alias.
        KeyPairGenerator keyPairGenerator = KeyPairGenerator.getInstance(
                KeyProperties.KEY_ALGORITHM_EC, "AndroidKeyStore");
        keyPairGenerator.initialize(
                new KeyGenParameterSpec.Builder("Key1", KeyProperties.PURPOSE_SIGN)
                        .setAlgorithmParameterSpec(new ECGenParameterSpec("secp256r1"))
                        .setDigests(KeyProperties.DIGEST_SHA256)
                        // Only permit the private key to be used if the user
                        // authenticated within the last five minutes.
                        .setUserAuthenticationRequired(true)
                        .setUserAuthenticationValidityDurationSeconds(5 * 60)
                        // Request an attestation with the message signature
                        .setAttestationChallenge(challenge)
                        .build());
        // Generate the key pair. This will result in calls to both generate_key() and
        // attest_key() at the keymaster2 HAL.
        KeyPair keyPair = keyPairGenerator.generateKeyPair();
        // Get the certificate chain
        KeyStore keyStore = KeyStore.getInstance("AndroidKeyStore");
        keyStore.load(null);
        Certificate[] certs = keyStore.getCertificateChain("Key1");
        // certs[0] is the attestation certificate. certs[1] signs certs[0], etc.,
        // up to certs[certs.length - 1].
        Log.d("CKVerifier", certs.toString());
        Log.d("CKVerifier", "Certs length: " + certs.length);
        for (int i = 0; i < certs.length; i++) {
            X509Certificate cert = (X509Certificate) certs[i];
            /*Log.d("CKVerifier", "Cert " + i + ": " + cert.getIssuerDN());
            Log.d("CKVerifier", "Complete cert: " + Numeric.toHexString(cert.getEncoded()));
            Log.d("CKVerifier", cert.getSigAlgName());
            Log.d("CKVerifier", cert.toString());
            Log.d("CKVerifier", cert.getPublicKey().getAlgorithm() + " " + cert.getPublicKey().toString());
            */
            if (i > 0) {
                continue;
            }
            byte[] attestationExtensionBytes = cert.getExtensionValue("1.3.6.1.4.1.11129.2.1.17");
            ASN1Primitive decodedSequence;
            try (ASN1InputStream asn1InputStream = new ASN1InputStream(attestationExtensionBytes)) {
                // The extension contains one object, a sequence, in the
                // Distinguished Encoding Rules (DER)-encoded form. Get the DER
                // bytes.
                byte[] derSequenceBytes = ((ASN1OctetString) asn1InputStream.readObject()).getOctets();
                // Decode the bytes as an ASN1 sequence object.
                try (ASN1InputStream seqInputStream = new ASN1InputStream(derSequenceBytes)) {
                    decodedSequence = (ASN1Primitive) seqInputStream.readObject();
                }
            }
            Log.d("CKVerifier", String.valueOf(decodedSequence));
            Log.d("CKVerifier", ASN1Dump.dumpAsString(decodedSequence));
        }

        return Arrays.stream(certs).map(cert -> {
            try {
                return Numeric.toHexString(cert.getEncoded());
            } catch (CertificateEncodingException e) {
                e.printStackTrace();
            }
            return "";
        }).collect(Collectors.joining("\n"));
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        // Make result view scrollable
        TextView certsView = findViewById(R.id.certificateTextView);
        certsView.setMovementMethod(new ScrollingMovementMethod());

        Button button = findViewById(R.id.goButton);
        button.setOnClickListener(view -> {
            EditText editTextPrivateKey = findViewById(R.id.editTextPrivateKey);
            String privateKey = editTextPrivateKey.getText().toString();

            try {
                Credentials credentials = Credentials.create(privateKey);
                String address = Keys.toChecksumAddress(credentials.getAddress());

                String nonceMessage = "Android CK Verification";
                Sign.SignatureData signature = Sign.signPrefixedMessage(nonceMessage.getBytes(StandardCharsets.UTF_8),
                        credentials.getEcKeyPair());
                Log.d("CKVerifier", "r: " + Numeric.toHexString(signature.getR()));
                Log.d("CKVerifier", "s: " + Numeric.toHexString(signature.getS()));
                Log.d("CKVerifier", "v: " + Numeric.toHexString(signature.getV()));

                byte[] hexSignature = new byte[65];
                System.arraycopy(signature.getR(), 0, hexSignature, 0, 32);
                System.arraycopy(signature.getS(), 0, hexSignature, 32, 32);
                System.arraycopy(signature.getV(), 0, hexSignature, 64, 1);

                String certData = getKeystore(hexSignature);
                Log.d("CKVerifier", address);
                Log.d("CKVerifier", certData);
                ClipboardManager clipboard = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
                ClipData clip = ClipData.newPlainText("Android CK certificates", certData);
                clipboard.setPrimaryClip(clip);

                certsView.setText(String.format("%s\n\nSuccess! Certificates are copied to the clipboard!", address));
            } catch (Exception e) {
                certsView.setText(e.getMessage());
                e.printStackTrace();
            }
        });
    }
}